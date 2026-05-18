'use strict';

// One-shot text translation via Mistral chat completions. Shared by the
// /translation/text HTTP route and the LiveKit translation agent so both use
// the same prompt + model.

const MISTRAL_CHAT_URL = 'https://api.mistral.ai/v1/chat/completions';

async function translateText({ apiKey, model, text, from, to }) {
  if (!text || !text.trim()) return '';
  if (from && from === to) return text;

  const sys =
    `You are a translator. Translate the user's message into ${to}. ` +
    `Reply with the translated text ONLY, no quotes, no explanation, ` +
    `no language tags. Preserve emojis and proper nouns. If the message ` +
    `is already in ${to}, return it unchanged.`;

  const r = await fetch(MISTRAL_CHAT_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: 'system', content: sys },
        { role: 'user', content: text },
      ],
      temperature: 0.2,
    }),
  });
  const body = await r.text();
  if (!r.ok) {
    throw new Error(`mistral_chat_error_${r.status}: ${body.slice(0, 200)}`);
  }
  const parsed = JSON.parse(body);
  return parsed?.choices?.[0]?.message?.content ?? '';
}

module.exports = { translateText };
