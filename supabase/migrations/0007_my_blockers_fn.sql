-- The `blocked_users` RLS only lets the *blocker* read their own rows,
-- so a user can list who *they* blocked but cannot directly find out
-- who has blocked *them*. We need that information to hide a
-- conversation on the blocked party's chat list when they get blocked
-- (otherwise messages-into-the-void).
--
-- This SECURITY DEFINER function returns the blocker ids that currently
-- point at the calling user (auth.uid()). No row data leaks — only the
-- blocker uuids are exposed, which the caller could otherwise discover
-- by trial-and-error anyway by trying to message the user.

create or replace function public.my_blockers()
returns table(blocker_id uuid)
language sql
security definer
set search_path = public
as $$
  select blocker from public.blocked_users where blocked = auth.uid();
$$;

revoke all on function public.my_blockers() from public;
grant execute on function public.my_blockers() to authenticated;
