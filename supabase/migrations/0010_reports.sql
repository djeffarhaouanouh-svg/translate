-- User-to-user moderation reports. Required for store distribution
-- (App Store §1.2 / Play Store UGC rules).
--
-- A `reports` row is created by the reporter; admins read the table via
-- service_role (so anonymous viewers can't see other people's reports).
-- The reported party is intentionally never told who reported them.

create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter    uuid not null references auth.users(id) on delete cascade,
  reported    uuid not null references auth.users(id) on delete cascade,
  reason      text not null check (reason in (
    'spam',
    'harassment',
    'fake_profile',
    'inappropriate_content',
    'underage',
    'scam',
    'other'
  )),
  details     text,
  created_at  timestamptz not null default now(),
  resolved    boolean not null default false,
  resolved_at timestamptz,
  resolved_by uuid references auth.users(id),
  check (reporter <> reported)
);

create index if not exists reports_reported_idx on public.reports (reported);
create index if not exists reports_reporter_idx on public.reports (reporter);
create index if not exists reports_pending_idx
  on public.reports (created_at desc)
  where not resolved;

alter table public.reports enable row level security;

-- Reporters insert their own rows only.
drop policy if exists "reporters_insert_own" on public.reports;
create policy "reporters_insert_own"
  on public.reports
  for insert
  to authenticated
  with check (auth.uid() = reporter);

-- Reporters can see (only) their own reports — lets the app surface a
-- "déjà signalé" indicator if needed without exposing other users'
-- reports.
drop policy if exists "reporters_select_own" on public.reports;
create policy "reporters_select_own"
  on public.reports
  for select
  to authenticated
  using (auth.uid() = reporter);
