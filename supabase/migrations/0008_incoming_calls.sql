-- Idempotent reset of `incoming_calls`: makes sure the table, the RLS
-- policies, and the realtime publication match what the Flutter client
-- expects. Safe to re-run on an environment where some pieces already
-- exist.

create table if not exists public.incoming_calls (
  id          uuid primary key default gen_random_uuid(),
  caller      uuid not null references auth.users(id) on delete cascade,
  callee      uuid not null references auth.users(id) on delete cascade,
  room_name   text not null,
  created_at  timestamptz not null default now()
);

create index if not exists incoming_calls_callee_idx
  on public.incoming_calls (callee);
create index if not exists incoming_calls_caller_idx
  on public.incoming_calls (caller);

alter table public.incoming_calls enable row level security;

-- Caller can insert their own outgoing-call rows.
drop policy if exists "caller_insert_own"   on public.incoming_calls;
drop policy if exists "caller can insert their own outgoing calls"
  on public.incoming_calls;
create policy "caller_insert_own"
  on public.incoming_calls
  for insert
  to authenticated
  with check (auth.uid() = caller);

-- Callee can read incoming rings addressed to them.
drop policy if exists "callee_select_own"   on public.incoming_calls;
drop policy if exists "callee can see their own incoming calls"
  on public.incoming_calls;
create policy "callee_select_own"
  on public.incoming_calls
  for select
  to authenticated
  using (auth.uid() = callee);

-- Either party may delete to close the ring (cancel / answer / decline).
drop policy if exists "either_party_delete" on public.incoming_calls;
drop policy if exists "caller or callee can delete"
  on public.incoming_calls;
create policy "either_party_delete"
  on public.incoming_calls
  for delete
  to authenticated
  using (auth.uid() = caller or auth.uid() = callee);

-- Realtime publication — required for the callee's INSERT subscription.
do $$
begin
  alter publication supabase_realtime add table public.incoming_calls;
exception
  when duplicate_object then null;
end$$;
