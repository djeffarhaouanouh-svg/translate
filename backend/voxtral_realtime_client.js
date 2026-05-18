'use strict';

// Thin wrapper around Mistral Voxtral realtime transcription over WebSocket.
//
// Lifecycle: caller creates one client per speaker, feeds 16 kHz PCM mono
// (Int16) frames via writePcm(), and listens on `onTranscript` for finalised
// utterances (Mistral commits when its internal VAD detects end-of-speech).
//
// NOTE: at the time of writing Mistral does not publish the exact JSON
// envelope for the realtime websocket. The shape used below is the most
// likely one given the REST `/v1/audio/transcriptions` schema and Mistral's
// other streaming endpoints; expect to adjust message keys after the first
// real handshake. All TODO markers below are the places to revisit.

const { WebSocket } = require('ws');
const { EventEmitter } = require('events');

const MISTRAL_REALTIME_URL =
  process.env.MISTRAL_REALTIME_URL?.trim() ||
  'wss://api.mistral.ai/v1/audio/transcriptions/stream';

class VoxtralRealtimeClient extends EventEmitter {
  /**
   * @param {object} opts
   * @param {string} opts.apiKey            Mistral API key.
   * @param {string} opts.model             e.g. "voxtral-mini-transcribe-realtime-2602".
   * @param {string} [opts.language]        BCP-47 primary subtag of the speaker.
   * @param {number} [opts.sampleRate=16000]
   */
  constructor({ apiKey, model, language, sampleRate = 16000 }) {
    super();
    this._apiKey = apiKey;
    this._model = model;
    this._language = language;
    this._sampleRate = sampleRate;
    /** @type {WebSocket | null} */
    this._ws = null;
    this._opened = false;
    this._closed = false;
    /** @type {Array<Buffer>} */
    this._sendBacklog = [];
  }

  async connect() {
    if (this._ws) return;
    this._ws = new WebSocket(MISTRAL_REALTIME_URL, {
      headers: { Authorization: `Bearer ${this._apiKey}` },
    });

    this._ws.on('open', () => {
      this._opened = true;
      // TODO(mistral): confirm the session-init payload. The shape below
      // mirrors Mistral's REST /v1/audio/transcriptions plus stream:true.
      const initMsg = {
        type: 'session.create',
        model: this._model,
        audio: {
          encoding: 'pcm_s16le',
          sample_rate: this._sampleRate,
          channels: 1,
        },
      };
      if (this._language) initMsg.language = this._language;
      this._send(JSON.stringify(initMsg));
      for (const chunk of this._sendBacklog) this._send(chunk);
      this._sendBacklog.length = 0;
      this.emit('open');
    });

    this._ws.on('message', (data, isBinary) => {
      if (isBinary) return; // Mistral realtime is text-frames only for events.
      let msg;
      try {
        msg = JSON.parse(data.toString('utf8'));
      } catch (e) {
        return;
      }
      // TODO(mistral): confirm the event names. Common patterns:
      //   { type: "transcript.delta", text: "..." }
      //   { type: "transcript.final", text: "..." }
      //   { type: "error", error: { message } }
      const type = msg.type || msg.event;
      if (type === 'transcript.final' || type === 'transcription.completed') {
        const text = msg.text || msg.transcript || '';
        if (text) this.emit('transcript', { text, final: true });
      } else if (type === 'transcript.delta' || type === 'transcription.delta') {
        const text = msg.text || msg.delta || '';
        if (text) this.emit('transcript', { text, final: false });
      } else if (type === 'error') {
        this.emit('error', new Error(msg.error?.message || 'mistral_realtime_error'));
      }
    });

    this._ws.on('error', (err) => this.emit('error', err));
    this._ws.on('close', (code, reason) => {
      this._closed = true;
      this.emit('close', { code, reason: reason?.toString() || '' });
    });
  }

  /** Feed a chunk of 16-bit PCM mono samples (Int16Array or Buffer). */
  writePcm(chunk) {
    if (this._closed) return;
    const buf = Buffer.isBuffer(chunk)
      ? chunk
      : Buffer.from(chunk.buffer, chunk.byteOffset, chunk.byteLength);
    if (!this._opened) {
      this._sendBacklog.push(buf);
      return;
    }
    // TODO(mistral): some realtime APIs require base64 inside a JSON envelope,
    // others accept raw binary frames. Trying raw binary first since it is
    // by far the most efficient option.
    this._send(buf);
  }

  _send(payload) {
    try {
      this._ws.send(payload);
    } catch (e) {
      this.emit('error', e);
    }
  }

  async close() {
    if (this._closed) return;
    this._closed = true;
    try {
      this._ws?.close();
    } catch (_) {}
  }
}

module.exports = { VoxtralRealtimeClient };
