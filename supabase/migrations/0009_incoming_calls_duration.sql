-- Add call-duration tracking on `incoming_calls` so the row survives as
-- history instead of being deleted when the call ends. Two new columns
-- + a SECURITY DEFINER helper that stamps the end timestamp and
-- computes the duration server-side.

alter table public.incoming_calls
  add column if not exists ended_at         timestamptz,
  add column if not exists duration_seconds integer;

-- Let the caller see their own outgoing-call history too — the old
-- policy only let the callee SELECT.
drop policy if exists "callee_select_own"        on public.incoming_calls;
drop policy if exists "caller_or_callee_select"  on public.incoming_calls;
create policy "caller_or_callee_select"
  on public.incoming_calls
  for select
  to authenticated
  using (auth.uid() = caller or auth.uid() = callee);

-- Either party can stamp ended_at / duration_seconds when the call ends.
drop policy if exists "either_party_update" on public.incoming_calls;
create policy "either_party_update"
  on public.incoming_calls
  for update
  to authenticated
  using (auth.uid() = caller or auth.uid() = callee)
  with check (auth.uid() = caller or auth.uid() = callee);

-- One-shot helper: stamps `ended_at = now()` and writes the duration
-- (`now() - created_at`) server-side so the client doesn't have to
-- re-fetch `created_at` first. Idempotent: a row that already has
-- `ended_at` is left untouched, so a double-leave from caller + callee
-- never overwrites the original duration.
create or replace function public.end_incoming_call(p_call_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.incoming_calls
     set ended_at         = now(),
         duration_seconds = greatest(
           0,
           extract(epoch from (now() - created_at))::int
         )
   where id = p_call_id
     and ended_at is null
     and (caller = auth.uid() or callee = auth.uid());
end;
$$;

revoke all on function public.end_incoming_call(uuid) from public;
grant execute on function public.end_incoming_call(uuid) to authenticated;
