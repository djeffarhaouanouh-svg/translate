-- Stores every device / browser the user has authorised to receive push
-- notifications. The backend reads this table via service-role and
-- fans out to Web Push (browser endpoints) + Firebase Cloud Messaging
-- (mobile FCM tokens) when an event needs to wake a user.
--
-- One row per (user, target). A user typically has multiple rows: one
-- per browser/device they've granted notification permission on.

create table if not exists public.notification_targets (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  platform    text not null check (platform in ('web', 'ios', 'android')),
  -- Web Push fields (RFC 8030). null on native rows.
  endpoint    text,
  p256dh      text,
  auth_key    text,
  -- Firebase Cloud Messaging token. null on web rows.
  fcm_token   text,
  -- Best-effort UA / device label, only for the user's own settings UI.
  user_agent  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Per-user uniqueness keyed on the actual transport identifier so we
-- never duplicate a row when the client re-registers on app open.
create unique index if not exists notification_targets_web_unique
  on public.notification_targets (user_id, endpoint)
  where platform = 'web';

create unique index if not exists notification_targets_native_unique
  on public.notification_targets (user_id, fcm_token)
  where platform in ('ios', 'android');

create index if not exists notification_targets_user_idx
  on public.notification_targets (user_id);

alter table public.notification_targets enable row level security;

-- A user can manage only their own targets. The backend reads
-- everyone's targets via the service-role key (bypasses RLS).
drop policy if exists "targets_owner_all" on public.notification_targets;
create policy "targets_owner_all"
  on public.notification_targets
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
