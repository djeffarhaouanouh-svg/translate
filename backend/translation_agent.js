'use strict';

// LiveKit translation agent. A "bot" participant that:
//   1. Joins a room as identity `xlate-bot`.
//   2. Subscribes to each *human* remote participant's microphone track.
//   3. Pipes their PCM into Mistral Voxtral realtime → text.
//   4. Translates the text via mistral-small-latest into every OTHER
//      participant's preferred language.
//   5. Synthesises the translated text via Voxtral TTS and publishes one
//      LocalAudioTrack PER target participant, named `xlate-for-<identity>`.
//
// Clients subscribe to the bot's tracks and mute the original speaker's
// track so the user only hears the translation.

const {
  Room,
  RoomEvent,
  TrackKind,
  AudioStream,
  AudioSource,
  AudioFrame,
  LocalAudioTrack,
  TrackPublishOptions,
  TrackSource,
} = require('@livekit/rtc-node');
const { AccessToken } = require('livekit-server-sdk');

const { VoxtralRealtimeClient } = require('./voxtral_realtime_client');
const { translateText } = require('./mistral_text_translate');
const { streamTtsPcm, DEFAULT_TTS_SAMPLE_RATE } = require('./mistral_tts_client');

const STT_SAMPLE_RATE = 16000;
const BOT_IDENTITY_PREFIX = 'xlate-bot';

/**
 * In-memory registry of active agents, keyed by `${url}|${roomName}`.
 * @type {Map<string, TranslationAgent>}
 */
const agents = new Map();

function agentKey(url, roomName) {
  return `${url}|${roomName}`;
}

function readLangsFromMetadata(metadataStr) {
  try {
    const meta = JSON.parse(metadataStr || '{}');
    return {
      sourceLang: typeof meta.sourceLang === 'string' ? meta.sourceLang : '',
      targetLang: typeof meta.targetLang === 'string' ? meta.targetLang : '',
    };
  } catch (_) {
    return { sourceLang: '', targetLang: '' };
  }
}

function primaryLanguageTag(bcp47) {
  const s = typeof bcp47 === 'string' ? bcp47.trim().toLowerCase() : '';
  if (!s) return '';
  const i = s.indexOf('-');
  return i === -1 ? s : s.slice(0, i);
}

class TranslationAgent {
  constructor({ url, apiKey, apiSecret, roomName, mistralConfig }) {
    this._url = url;
    this._apiKey = apiKey;
    this._apiSecret = apiSecret;
    this._roomName = roomName;
    this._mistral = mistralConfig;
    this._botIdentity = `${BOT_IDENTITY_PREFIX}-${roomName}`;

    /** @type {Room | null} */
    this._room = null;
    /** Per-speaker pipeline state, keyed by remote participant identity. */
    this._speakers = new Map();
    /** Outbound translation tracks, keyed by `${forIdentity}|${language}`. */
    this._outbound = new Map();
    this._closed = false;
  }

  async start() {
    const at = new AccessToken(this._apiKey, this._apiSecret, {
      identity: this._botIdentity,
      name: 'Translator',
      metadata: JSON.stringify({ bot: 'translation' }),
    });
    at.addGrant({
      roomJoin: true,
      room: this._roomName,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
      hidden: false,
    });
    const token = await at.toJwt();

    this._room = new Room();
    this._room.on(RoomEvent.TrackSubscribed, (track, pub, participant) =>
      this._onTrackSubscribed(track, pub, participant).catch((e) =>
        console.error(`[xlate-agent ${this._roomName}] onTrackSubscribed`, e),
      ),
    );
    this._room.on(RoomEvent.ParticipantDisconnected, (p) =>
      this._teardownSpeaker(p.identity),
    );
    this._room.on(RoomEvent.Disconnected, () => {
      console.log(`[xlate-agent ${this._roomName}] disconnected`);
      this._closed = true;
      agents.delete(agentKey(this._url, this._roomName));
    });

    await this._room.connect(this._url, token, { autoSubscribe: true });
    console.log(
      `[xlate-agent ${this._roomName}] connected as ${this._botIdentity}`,
    );
  }

  async _onTrackSubscribed(track, pub, participant) {
    if (participant.identity.startsWith(BOT_IDENTITY_PREFIX)) return;
    if (track.kind !== TrackKind.KIND_AUDIO) return;
    // Only the published microphone, never screen-share audio.
    if (pub.source && pub.source !== TrackSource.SOURCE_MICROPHONE) return;

    const { sourceLang } = readLangsFromMetadata(participant.metadata);
    const speakerLang = primaryLanguageTag(sourceLang);
    if (!speakerLang) {
      console.warn(
        `[xlate-agent ${this._roomName}] no sourceLang for ${participant.identity}; skipping`,
      );
      return;
    }

    if (this._speakers.has(participant.identity)) return;
    console.log(
      `[xlate-agent ${this._roomName}] subscribing to ${participant.identity} (lang=${speakerLang})`,
    );

    const stt = new VoxtralRealtimeClient({
      apiKey: this._mistral.apiKey,
      model: this._mistral.sttModel,
      language: speakerLang,
      sampleRate: STT_SAMPLE_RATE,
    });
    stt.on('error', (e) =>
      console.error(`[xlate-agent ${this._roomName}] stt error`, e),
    );
    stt.on('transcript', ({ text, final }) => {
      if (!final) return;
      this._onUtterance(participant.identity, speakerLang, text).catch((e) =>
        console.error(`[xlate-agent ${this._roomName}] onUtterance`, e),
      );
    });
    await stt.connect();

    const audioStream = new AudioStream(track, {
      sampleRate: STT_SAMPLE_RATE,
      numChannels: 1,
    });
    const state = { stt, audioStream, stopped: false };
    this._speakers.set(participant.identity, state);

    (async () => {
      try {
        for await (const frame of audioStream) {
          if (state.stopped) break;
          // frame.data is Int16Array — Mistral expects pcm_s16le bytes.
          stt.writePcm(frame.data);
        }
      } catch (e) {
        if (!state.stopped) {
          console.error(`[xlate-agent ${this._roomName}] audio loop`, e);
        }
      }
    })();
  }

  async _onUtterance(speakerIdentity, speakerLang, text) {
    if (this._closed) return;
    if (!text.trim()) return;

    // Translate ONCE per target language across all listeners.
    const listenersByLang = new Map();
    for (const p of this._room.remoteParticipants.values()) {
      if (p.identity === speakerIdentity) continue;
      if (p.identity.startsWith(BOT_IDENTITY_PREFIX)) continue;
      const { sourceLang: listenerLang } = readLangsFromMetadata(p.metadata);
      const lang = primaryLanguageTag(listenerLang);
      if (!lang || lang === speakerLang) continue;
      if (!listenersByLang.has(lang)) listenersByLang.set(lang, []);
      listenersByLang.get(lang).push(p.identity);
    }

    for (const [targetLang, listeners] of listenersByLang) {
      try {
        const translated = await translateText({
          apiKey: this._mistral.apiKey,
          model: this._mistral.textModel,
          text,
          from: speakerLang,
          to: targetLang,
        });
        if (!translated.trim()) continue;
        for (const listenerIdentity of listeners) {
          await this._speakTo(listenerIdentity, targetLang, translated);
        }
      } catch (e) {
        console.error(`[xlate-agent ${this._roomName}] translate→${targetLang}`, e);
      }
    }
  }

  async _ensureOutbound(forIdentity, language) {
    const key = `${forIdentity}|${language}`;
    if (this._outbound.has(key)) return this._outbound.get(key);

    const source = new AudioSource(DEFAULT_TTS_SAMPLE_RATE, 1);
    const trackName = `xlate-for-${forIdentity}`;
    const track = LocalAudioTrack.createAudioTrack(trackName, source);
    const opts = new TrackPublishOptions();
    opts.source = TrackSource.SOURCE_MICROPHONE;
    // Carry the routing info on the publication so clients can pick the
    // right translated track to play and mute the original speaker.
    opts.name = trackName;
    opts.stream = `xlate|${forIdentity}|${language}`;
    await this._room.localParticipant.publishTrack(track, opts);

    const entry = { source, track };
    this._outbound.set(key, entry);
    return entry;
  }

  async _speakTo(listenerIdentity, targetLang, translatedText) {
    const { source } = await this._ensureOutbound(listenerIdentity, targetLang);
    const CHUNK_SAMPLES = DEFAULT_TTS_SAMPLE_RATE / 50; // 20 ms frames
    for await (const pcm of streamTtsPcm({
      apiKey: this._mistral.apiKey,
      model: this._mistral.ttsModel,
      voiceId: this._mistral.ttsVoiceId || undefined,
      text: translatedText,
      sampleRate: DEFAULT_TTS_SAMPLE_RATE,
    })) {
      // Split into 20 ms frames so LiveKit jitter buffer stays happy.
      for (let off = 0; off < pcm.length; off += CHUNK_SAMPLES) {
        const slice = pcm.subarray(off, Math.min(off + CHUNK_SAMPLES, pcm.length));
        const frame = new AudioFrame(
          slice,
          DEFAULT_TTS_SAMPLE_RATE,
          1,
          slice.length,
        );
        await source.captureFrame(frame);
      }
    }
  }

  _teardownSpeaker(identity) {
    const state = this._speakers.get(identity);
    if (!state) return;
    state.stopped = true;
    try {
      state.stt.close();
    } catch (_) {}
    try {
      state.audioStream.close?.();
    } catch (_) {}
    this._speakers.delete(identity);
  }

  async stop() {
    if (this._closed) return;
    this._closed = true;
    for (const id of [...this._speakers.keys()]) this._teardownSpeaker(id);
    try {
      await this._room?.disconnect();
    } catch (_) {}
    agents.delete(agentKey(this._url, this._roomName));
  }
}

/**
 * Idempotently make sure a translation agent is running in the given room.
 * Returns the bot identity so the client can recognise / hide it in UI.
 */
async function ensureTranslationAgent({
  url,
  apiKey,
  apiSecret,
  roomName,
  mistralConfig,
}) {
  const key = agentKey(url, roomName);
  const existing = agents.get(key);
  if (existing && !existing._closed) {
    return { identity: existing._botIdentity, reused: true };
  }
  const agent = new TranslationAgent({
    url,
    apiKey,
    apiSecret,
    roomName,
    mistralConfig,
  });
  agents.set(key, agent);
  try {
    await agent.start();
  } catch (e) {
    agents.delete(key);
    throw e;
  }
  return { identity: agent._botIdentity, reused: false };
}

async function stopTranslationAgent({ url, roomName }) {
  const agent = agents.get(agentKey(url, roomName));
  if (!agent) return false;
  await agent.stop();
  return true;
}

module.exports = {
  ensureTranslationAgent,
  stopTranslationAgent,
  BOT_IDENTITY_PREFIX,
};
