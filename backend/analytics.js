'use strict';

// Analytics event ingestion for the off-site admin dashboard.
//
// Two write paths, both using the Supabase service-role key (the
// `analytics_events` table is RLS-locked — see migration 0017):
//
//   * track(fields)                — backend-internal events (a
//                                    translation session was minted, an
//                                    OpenAI call failed, …). Fire-and-
//                                    forget, never throws.
//   * ingestEvents(uid, evs, ctry) — a batch POSTed by the app to
//                                    /api/events. Each event is
//                                    validated / clamped before insert.
//
// Without SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY (already required by
// notify.js / stripe.js) every function here is a safe no-op.

const SUPABASE_URL = process.env.SUPABASE_URL?.trim();
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim();

let _supabase = null;
function supabase() {
  if (_supabase) return _supabase;
  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) return null;
  const { createClient } = require('@supabase/supabase-js');
  _supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return _supabase;
}

// ─── request enrichment ───────────────────────────────────────────────────

// CDN / proxy headers that carry an ISO-3166 alpha-2 country. Checked in
// order; the first plausible value wins. Empty when the backend sits
// behind no geo-aware proxy — the client's locale-region hint is the
// fallback then (see cleanEvent → country).
const COUNTRY_HEADERS = [
  'cf-ipcountry', // Cloudflare
  'x-vercel-ip-country', // Vercel
  'x-appengine-country', // Google App Engine
  'x-geo-country',
  'x-country-code',
];

/** Best-effort ISO-3166 alpha-2 country for a request, or null. */
function countryFromReq(req) {
  for (const h of COUNTRY_HEADERS) {
    const raw = req.headers?.[h];
    const v = typeof raw === 'string' ? raw.trim().toUpperCase() : '';
    // 'XX' / 'T1' (Tor) etc. are placeholders some CDNs emit — drop them.
    if (/^[A-Z]{2}$/.test(v) && v !== 'XX' && v !== 'T1') return v;
  }
  return null;
}

// ─── event validation ─────────────────────────────────────────────────────

/** snake_case identifier, ≤ 48 chars — keeps the `event` column tidy. */
const EVENT_RE = /^[a-z][a-z0-9_]{0,47}$/;
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
/** Cap a single ingest batch — a misbehaving client can't flood the table. */
const MAX_BATCH = 50;

function clampStr(v, max) {
  return typeof v === 'string' && v.length > 0 ? v.slice(0, max) : null;
}

function clampInt(v) {
  const n = Number(v);
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

/**
 * Parse a client-supplied ISO-8601 timestamp. Events are buffered on
 * the device and flushed in batches (and may sit through an app
 * backgrounding), so the client's own time is far more accurate than
 * the insert time. Rejected — caller falls back to the column default
 * now() — when missing, unparseable, or so far off it smells like a
 * broken device clock.
 */
function clampTs(v) {
  if (typeof v !== 'string') return null;
  const t = Date.parse(v);
  if (!Number.isFinite(t)) return null;
  const now = Date.now();
  if (t > now + 2 * 60 * 1000) return null; // > 2 min in the future
  if (t < now - 7 * 24 * 3600 * 1000) return null; // > 7 days stale
  return new Date(t).toISOString();
}

/**
 * Validate / clamp one raw event object from the wire. Returns a row
 * ready for insert, or null when `event` is missing / malformed.
 * `serverCountry` (CDN geo header — the network-IP country) wins over
 * the client's locale-region hint, which is only a weak fallback.
 */
function cleanEvent(raw, serverCountry) {
  if (!raw || typeof raw !== 'object') return null;
  const event = typeof raw.event === 'string' ? raw.event.trim() : '';
  if (!EVENT_RE.test(event)) return null;

  let props = {};
  if (raw.props && typeof raw.props === 'object' && !Array.isArray(raw.props)) {
    try {
      // Round-trip drops functions / undefined and caps pathological size.
      const json = JSON.stringify(raw.props);
      if (json.length <= 4000) props = JSON.parse(json);
    } catch (_) {
      props = {};
    }
  }

  const clientCountry = clampStr(raw.country, 2);
  const row = {
    event,
    session_id: UUID_RE.test(raw.session_id || '') ? raw.session_id : null,
    room_name: clampStr(raw.room_name, 64),
    lang_from: clampStr(raw.lang_from, 16),
    lang_to: clampStr(raw.lang_to, 16),
    country: serverCountry || (clientCountry ? clientCountry.toUpperCase() : null),
    latency_ms: clampInt(raw.latency_ms),
    props,
  };
  // Only set created_at when the client sent a trustworthy timestamp —
  // otherwise omit the key so the column default now() applies (an
  // explicit null would violate the NOT NULL constraint).
  const ts = clampTs(raw.ts);
  if (ts) row.created_at = ts;
  return row;
}

// ─── write paths ──────────────────────────────────────────────────────────

/**
 * Insert a batch of app-emitted events. `userId` is null for guests.
 * Returns { inserted } or { error }. Never throws.
 */
async function ingestEvents(userId, rawEvents, serverCountry) {
  const sb = supabase();
  if (!sb) return { error: 'supabase-not-configured' };
  if (!Array.isArray(rawEvents) || rawEvents.length === 0) {
    return { inserted: 0 };
  }
  const rows = rawEvents
    .slice(0, MAX_BATCH)
    .map((e) => cleanEvent(e, serverCountry))
    .filter(Boolean)
    .map((e) => ({ ...e, user_id: userId || null }));
  if (rows.length === 0) return { inserted: 0 };
  try {
    const { error } = await sb.from('analytics_events').insert(rows);
    if (error) return { error: error.message };
    return { inserted: rows.length };
  } catch (e) {
    return { error: e?.message || String(e) };
  }
}

/**
 * Record one backend-internal event. Fire-and-forget: the caller does
 * not await it and it never throws — analytics must never break a real
 * request path. `fields` may carry any of the typed columns plus props.
 */
function track(fields) {
  const sb = supabase();
  if (!sb) return;
  const ev = cleanEvent(fields, fields?.country || null);
  if (!ev) return;
  // Backend events may set user_id explicitly; cleanEvent doesn't carry it.
  const row = { ...ev, user_id: fields.user_id || null };
  Promise.resolve(sb.from('analytics_events').insert(row)).then(
    ({ error }) => {
      if (error) {
        // eslint-disable-next-line no-console
        console.error('[analytics] track insert failed:', error.message);
      }
    },
    (e) => {
      // eslint-disable-next-line no-console
      console.error('[analytics] track threw:', e?.message || e);
    },
  );
}

module.exports = { track, ingestEvents, countryFromReq };
