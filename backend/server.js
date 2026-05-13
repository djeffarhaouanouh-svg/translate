'use strict';

// LiveKit token API + optional Flutter web UI (folder ./web from Docker build).

const fs = require('fs');
const path = require('path');
const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const { AccessToken } = require('livekit-server-sdk');

dotenv.config();

const LIVEKIT_URL = process.env.LIVEKIT_URL?.trim();
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY?.trim();
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET?.trim();
const OPENAI_API_KEY = process.env.OPENAI_API_KEY?.trim();
const PORT = Number(process.env.PORT || 8787);

const OPENAI_TRANSLATION_CLIENT_SECRETS =
  'https://api.openai.com/v1/realtime/translations/client_secrets';
const OPENAI_TRANSLATION_CALLS = 'https://api.openai.com/v1/realtime/translations/calls';

const webPath = path.join(__dirname, 'web');
const webIndex = path.join(webPath, 'index.html');
const hasWebUi = fs.existsSync(webIndex);

function assertEnv() {
  const missing = [];
  if (!LIVEKIT_URL) missing.push('LIVEKIT_URL');
  if (!LIVEKIT_API_KEY) missing.push('LIVEKIT_API_KEY');
  if (!LIVEKIT_API_SECRET) missing.push('LIVEKIT_API_SECRET');
  if (missing.length) {
    throw new Error(`Missing env: ${missing.join(', ')}`);
  }
}

function assertOpenAI() {
  if (!OPENAI_API_KEY) {
    throw new Error('Missing OPENAI_API_KEY');
  }
}

function primaryLanguageTag(bcp47) {
  const s = typeof bcp47 === 'string' ? bcp47.trim().toLowerCase() : '';
  if (!s) return '';
  const i = s.indexOf('-');
  return i === -1 ? s : s.slice(0, i);
}

function isReasonableLanguageTag(tag) {
  return typeof tag === 'string' && /^[a-z]{2,3}(-[a-z0-9]{1,8})?$/.test(tag);
}

const ROOM_RE = /^[a-zA-Z0-9_-]{3,64}$/;
const IDENTITY_RE = /^[a-zA-Z0-9_.:-]{1,128}$/;

function sanitizeRoomName(name) {
  if (typeof name !== 'string' || !ROOM_RE.test(name)) {
    return null;
  }
  return name;
}

function sanitizeIdentity(id) {
  if (typeof id !== 'string' || !IDENTITY_RE.test(id)) {
    return null;
  }
  return id;
}

const app = express();
app.use(cors());

// Raw SDP body (not JSON) — must run before express.json().
app.post(
  '/translation/realtime/calls',
  express.text({ limit: '1mb', type: '*/*' }),
  async (req, res) => {
    const auth = req.headers.authorization;
    const m = typeof auth === 'string' ? /^Bearer\s+(.+)$/i.exec(auth.trim()) : null;
    const clientSecret = m ? m[1] : '';
    const sdpOffer = typeof req.body === 'string' ? req.body : '';
    if (!clientSecret || !sdpOffer.trim()) {
      return res.status(400).json({ error: 'missing_client_secret_or_sdp' });
    }
    try {
      const r = await fetch(OPENAI_TRANSLATION_CALLS, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${clientSecret}`,
          'Content-Type': 'application/sdp',
        },
        body: sdpOffer,
      });
      const answer = await r.text();
      return res.status(r.status).type('application/sdp').send(answer);
    } catch (e) {
      // eslint-disable-next-line no-console
      console.error('translation calls proxy', e);
      return res.status(502).json({ error: 'openai_unreachable' });
    }
  },
);

app.use(express.json({ limit: '16kb' }));

app.get('/health', (_req, res) => {
  res.json({ ok: true, webUi: hasWebUi });
});

app.get('/api', (_req, res) => {
  res.json({
    service: 'livekit-translate',
    webUi: hasWebUi,
    routes: {
      health: 'GET /health',
      livekitToken: 'POST /livekit/token',
      translationSession: 'POST /translation/realtime/session',
      translationCalls: 'POST /translation/realtime/calls (SDP relay, Authorization: Bearer ephemeral)',
    },
  });
});

/**
 * POST /livekit/token
 * Body: { roomName, identity, displayName?, sourceLang?, targetLang? }
 * Participant metadata (for a future OpenAI Realtime bridge):
 * - sourceLang: this participant's spoken language (BCP-47). Translate the remote participant's speech into this language for this participant to hear.
 * - targetLang: the remote participant's spoken language (BCP-47). Translate this participant's speech into this language for the remote participant to hear.
 */
app.post('/livekit/token', async (req, res) => {
  try {
    assertEnv();
  } catch (e) {
    return res.status(500).json({ error: 'server_misconfigured' });
  }

  const { roomName, identity, displayName, sourceLang, targetLang } = req.body || {};
  const room = sanitizeRoomName(roomName);
  const id = sanitizeIdentity(identity);
  if (!room || !id) {
    return res.status(400).json({ error: 'invalid_room_or_identity' });
  }

  const name =
    typeof displayName === 'string' && displayName.length > 0 && displayName.length <= 64
      ? displayName.slice(0, 64)
      : undefined;

  const at = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
    identity: id,
    name,
    metadata: JSON.stringify({
      sourceLang: typeof sourceLang === 'string' ? sourceLang.slice(0, 16) : '',
      targetLang: typeof targetLang === 'string' ? targetLang.slice(0, 16) : '',
    }),
  });

  at.addGrant({
    roomJoin: true,
    room,
    canPublish: true,
    canSubscribe: true,
  });

  const token = await at.toJwt();

  return res.json({
    url: LIVEKIT_URL,
    token,
    roomName: room,
  });
});

/**
 * POST /translation/realtime/session
 * Body: { outputLanguage: "fr" }  (BCP-47; primary subtag is used)
 * Proxies OpenAI Realtime Translation client_secrets (short-lived key for WebRTC).
 */
app.post('/translation/realtime/session', async (req, res) => {
  try {
    assertOpenAI();
  } catch (e) {
    return res.status(500).json({ error: 'openai_misconfigured' });
  }

  const raw = req.body?.outputLanguage;
  const tag = primaryLanguageTag(raw);
  if (!tag || !isReasonableLanguageTag(tag)) {
    return res.status(400).json({ error: 'invalid_output_language' });
  }

  try {
    const r = await fetch(OPENAI_TRANSLATION_CLIENT_SECRETS, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        session: {
          model: 'gpt-realtime-translate',
          audio: {
            input: {
              transcription: { model: 'gpt-realtime-whisper' },
              noise_reduction: { type: 'near_field' },
            },
            output: { language: tag },
          },
        },
      }),
    });
    const text = await r.text();
    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch (_) {
      return res.status(502).json({ error: 'openai_bad_response', body: text.slice(0, 200) });
    }
    return res.status(r.status).json(parsed);
  } catch (e) {
    // eslint-disable-next-line no-console
    console.error('translation session', e);
    return res.status(502).json({ error: 'openai_unreachable' });
  }
});

if (hasWebUi) {
  app.use(express.static(webPath));
  app.use((req, res, next) => {
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      return next();
    }
    const p = req.path || '';
    if (
      p.startsWith('/livekit') ||
      p === '/health' ||
      p.startsWith('/translation') ||
      p === '/api'
    ) {
      return next();
    }
    return res.sendFile(webIndex, (err) => (err ? next(err) : undefined));
  });
} else {
  app.get('/', (_req, res) => {
    res.type('application/json').send(
      JSON.stringify(
        {
          service: 'livekit-translate-token-api',
          hint: 'Build with Docker to bundle Flutter web in ./web',
          routes: {
            health: 'GET /health',
            livekitToken: 'POST /livekit/token',
            translationSession: 'POST /translation/realtime/session',
            translationCalls: 'POST /translation/realtime/calls',
          },
        },
        null,
        2,
      ),
    );
  });
}

app.listen(PORT, '0.0.0.0', () => {
  // eslint-disable-next-line no-console
  console.log(
    `Listening on http://0.0.0.0:${PORT} (web UI: ${hasWebUi ? 'yes' : 'no'})`,
  );
});
