-- Event log backing the off-site admin dashboard (Next.js / Supabase).
--
-- Every meaningful action the app or backend performs lands here as one
-- row. The dashboard reads aggregates from this single table — live
-- users, call volume, language pairs, countries, translation latency,
-- errors, retention cohorts, cost inputs.
--
-- Write paths (the table is service-role-only — see RLS below):
--   * App  → POST /api/events  → backend inserts with the service key.
--   * Backend internal events  → analytics.track() inserts directly.
--
-- `event` is intentionally an open text column (no CHECK / enum) so a
-- new event type never needs a migration. Anything beyond the typed
-- columns goes in `props` (jsonb).

create table if not exists public.analytics_events (
  id          bigint generated always as identity primary key,
  -- Null for guest-call traffic (joined via invite link, no account)
  -- and for some backend-side events.
  user_id     uuid references auth.users(id) on delete set null,
  -- Groups every event from one app session (one app launch). Minted
  -- client-side; powers retention (D1/D7/D30) and recurring-user counts.
  session_id  uuid,
  event       text not null,
  room_name   text,
  -- BCP-47 primary subtags of the translation direction, when relevant.
  lang_from   text,
  lang_to     text,
  -- ISO-3166 alpha-2, best effort: a CDN geo header server-side, else
  -- the device locale's region sent by the client. Upper-cased.
  country     text,
  -- Generic latency bucket (pipeline setup, first audio, …). ms.
  latency_ms  integer,
  props       jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);

-- Dashboard query shapes: "all rows of event X in window", "this user's
-- timeline" (retention), and plain time-range scans.
create index if not exists analytics_events_event_time_idx
  on public.analytics_events (event, created_at desc);
create index if not exists analytics_events_user_time_idx
  on public.analytics_events (user_id, created_at desc)
  where user_id is not null;
create index if not exists analytics_events_time_idx
  on public.analytics_events (created_at desc);

-- Service-role only. RLS is enabled with ZERO policies, so the anon /
-- authenticated keys can neither read nor write this table. The app
-- never touches it directly — it POSTs to /api/events, and both the
-- backend and the admin dashboard use the service-role key (which
-- bypasses RLS).
alter table public.analytics_events enable row level security;

-- ─── admin gating ─────────────────────────────────────────────────────────
-- Flag read by the off-site dashboard's Supabase-Auth login: only
-- profiles with is_admin = true may open the admin. Defaults false, so
-- granting access is an explicit, deliberate UPDATE.
alter table public.profiles
  add column if not exists is_admin boolean not null default false;
