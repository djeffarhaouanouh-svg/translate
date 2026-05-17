-- Required by Apple App Store §5.1.1(v) and Google Play UGC policy:
-- users must be able to permanently delete their account from inside
-- the app. Removing the row from `auth.users` cascades through every
-- table whose FK references `auth.users(id) on delete cascade`
-- (profiles, friendships, messages, likes, blocked_users,
--  incoming_calls, reports, notification_targets), so a single DELETE
-- on auth.users wipes every trace of the user.
--
-- A SECURITY DEFINER function is needed because regular clients can't
-- DELETE from auth.users directly. The function pulls the caller's
-- uid from auth.uid() so it can only ever delete the *caller's* row —
-- never someone else's.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;
  delete from auth.users where id = v_uid;
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
