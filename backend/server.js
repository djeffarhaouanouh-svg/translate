'use strict';

// LiveKit token API (deploy trigger: edit this file to force Railway rebuild when using watchPatterns on backend/**).

const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const { AccessToken } = require('livekit-server-sdk');

dotenv.config();

const LIVEKIT_URL = process.env.LIVEKIT_URL;
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY;
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET;
const PORT = Number(process.env.PORT || 8787);

function assertEnv() {
  const missing = [];
  if (!LIVEKIT_URL) missing.push('LIVEKIT_URL');
  if (!LIVEKIT_API_KEY) missing.push('LIVEKIT_API_KEY');
  if (!LIVEKIT_API_SECRET) missing.push('LIVEKIT_API_SECRET');
  if (missing.length) {
    throw new Error(`Missing env: ${missing.join(', ')}`);
  }
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
app.use(express.json({ limit: '16kb' }));

app.get('/', (_req, res) => {
  res.type('application/json').send(
    JSON.stringify(
      {
        service: 'livekit-translate-token-api',
        routes: {
          health: 'GET /health',
          livekitToken: 'POST /livekit/token (JSON body: roomName, identity, displayName, …)',
        },
      },
      null,
      2,
    ),
  );
});

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

/**
 * POST /livekit/token
 * Body: { roomName, identity, displayName?, sourceLang?, targetLang? }
 * sourceLang/targetLang reserved for future OpenAI Realtime translation routing.
 */
app.post('/livekit/token', (req, res) => {
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

  const token = at.toJwt();

  return res.json({
    url: LIVEKIT_URL,
    token,
    roomName: room,
  });
});

/**
 * Reserved: issue short-lived client secret or session for OpenAI Realtime.
 * Implement with server-side OPENAI_API_KEY only — never expose to the Flutter app.
 */
app.post('/translation/realtime/session', (_req, res) => {
  return res.status(501).json({
    error: 'not_implemented',
    hint: 'Add OpenAI Realtime session creation here; keep API keys on the server.',
  });
});

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`Token API listening on http://0.0.0.0:${PORT}`);
});
