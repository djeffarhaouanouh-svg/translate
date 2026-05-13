-- Profile + friendships backing Onglet 1 (search) and Onglet 3 (profile).
-- Idempotent: re-running is safe; existing tables / columns are preserved
-- and missing pieces are added.

-- ─── profiles ─────────────────────────────────────────────────────────────
create table if not exists public.profiles (
  id uuid primary key,
  handle text,
  display_name text not null,
  language text not null default '',
  avatar_color text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Defensive: bring older table shapes in line.
alter table public.profiles add column if not exists handle text;
alter table public.profiles add column if not exists avatar_color text;
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

-- A unique handle lets us namespace future "@mentions" without collisions.
do $$
begin
  alter table public.profiles add constraint profiles_handle_unique unique (handle);
exception when duplicate_object then null;
end$$;

create index if not exists profiles_display_name_lower_idx
  on public.profiles (lower(display_name));

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
create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester uuid not null,
  addressee uuid not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

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

-- ─── Realtime publication ────────────────────────────────────────────────
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
