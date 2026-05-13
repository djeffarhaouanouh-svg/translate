-- Profile + friendships backing the Onglet 1 friend-search page.
-- Idempotent: if the tables already exist (you created them in the dashboard),
-- only the RLS policies / indexes / realtime publication entries that are
-- missing get added.

-- ─── profiles ─────────────────────────────────────────────────────────────
create table if not exists public.profiles (
  id uuid primary key,
  first_name text not null,
  source_lang text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists profiles_first_name_lower_idx
  on public.profiles (lower(first_name));

alter table public.profiles enable row level security;

drop policy if exists "anon_read_profiles" on public.profiles;
create policy "anon_read_profiles"
  on public.profiles for select using (true);

drop policy if exists "anon_insert_profiles" on public.profiles;
create policy "anon_insert_profiles"
  on public.profiles for insert with check (true);

drop policy if exists "anon_update_profiles" on public.profiles;
create policy "anon_update_profiles"
  on public.profiles for update using (true);

-- ─── friendships ──────────────────────────────────────────────────────────
-- The unique (requester, addressee) constraint prevents duplicate requests in
-- the same direction. The app treats (A→B) and (B→A) as the same relation by
-- querying both rows.
create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester uuid not null,
  addressee uuid not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

-- Defensive: existing dashboards may have created the table before
-- responded_at was part of the schema.
alter table public.friendships
  add column if not exists responded_at timestamptz;

do $$
begin
  alter table public.friendships
    add constraint friendships_pair_unique unique (requester, addressee);
exception when duplicate_object then null;
end$$;

create index if not exists friendships_requester_idx on public.friendships (requester);
create index if not exists friendships_addressee_idx on public.friendships (addressee);

alter table public.friendships enable row level security;

drop policy if exists "anon_all_friendships" on public.friendships;
create policy "anon_all_friendships"
  on public.friendships for all using (true) with check (true);

-- Realtime for live status changes (pending → accepted etc.).
do $$
begin
  alter publication supabase_realtime add table public.profiles;
exception when duplicate_object then null;
end$$;

do $$
begin
  alter publication supabase_realtime add table public.friendships;
exception when duplicate_object then null;
end$$;
