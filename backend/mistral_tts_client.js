'use strict';

// Mistral Voxtral TTS — POST /v1/audio/speech with stream:true.
//
// Mistral streams audio chunks as Server-Sent Events when stream=true. Each
// SSE event carries base64-encoded audio bytes; we decode and yield Int16
// PCM frames at the configured sample rate so they can be fed straight into
// a LiveKit AudioSource.captureFrame().

const MISTRAL_TTS_URL = 'https://api.mistral.ai/v1/audio/speech';
const DEFAULT_SAMPLE_RATE = 24000;

/**
 * Yields Int16Array PCM frames for the given text.
 *
 * Choosing response_format=pcm: Mistral returns raw little-endian float32
 * samples per their docs when format=pcm. We convert to int16 to feed
 * @livekit/rtc-node's AudioSource which expects Int16.
 *
 * @returns {AsyncGenerator<Int16Array>}
 */
async function* streamTtsPcm({ apiKey, model, voiceId, text, sampleRate = DEFAULT_SAMPLE_RATE }) {
  if (!text || !text.trim()) return;
  const body = {
    model,
    input: text,
    response_format: 'pcm',
    stream: true,
    sample_rate: sampleRate,
  };
  if (voiceId) body.voice_id = voiceId;

  const r = await fetch(MISTRAL_TTS_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
      Accept: 'text/event-stream',
    },
    body: JSON.stringify(body),
  });

  if (!r.ok) {
    const errBody = await r.text();
    throw new Error(`mistral_tts_error_${r.status}: ${errBody.slice(0, 200)}`);
  }

  // Path 1: non-streaming JSON response (some accounts / models ignore stream)
  const contentType = r.headers.get('content-type') || '';
  if (!contentType.includes('event-stream')) {
    const json = await r.json();
    const b64 = json.audio_data || json.audio;
    if (typeof b64 === 'string') yield float32B64ToInt16(b64);
    return;
  }

  // Path 2: SSE — split on \n\n, each block has `data: { audio_data: <b64> }`.
  const reader = r.body.getReader();
  const decoder = new TextDecoder('utf-8');
  let buffer = '';
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    let idx;
    while ((idx = buffer.indexOf('\n\n')) !== -1) {
      const block = buffer.slice(0, idx);
      buffer = buffer.slice(idx + 2);
      const line = block.split('\n').find((l) => l.startsWith('data:'));
      if (!line) continue;
      const payload = line.slice(5).trim();
      if (!payload || payload === '[DONE]') continue;
      try {
        const ev = JSON.parse(payload);
        const b64 = ev.audio_data || ev.audio || ev.delta;
        if (typeof b64 === 'string' && b64) yield float32B64ToInt16(b64);
      } catch (_) {
        // ignore non-JSON keep-alive frames
      }
    }
  }
}

function float32B64ToInt16(b64) {
  const buf = Buffer.from(b64, 'base64');
  const f32 = new Float32Array(buf.buffer, buf.byteOffset, buf.byteLength / 4);
  const i16 = new Int16Array(f32.length);
  for (let i = 0; i < f32.length; i++) {
    let s = f32[i];
    if (s > 1) s = 1;
    else if (s < -1) s = -1;
    i16[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
  }
  return i16;
}

module.exports = { streamTtsPcm, DEFAULT_TTS_SAMPLE_RATE: DEFAULT_SAMPLE_RATE };
