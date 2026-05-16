-- The `likes` table RLS lets a user delete only the likes they *gave*
-- (auth.uid() = liker), which means the cascade we want when the user
-- removes their Discover photo — "wipe every like row pointing at me" —
-- silently fails because the caller is the `liked`, not the `liker`.
--
-- This SECURITY DEFINER function deletes the received likes on behalf of
-- the current user. It takes no parameters and pulls the target id from
-- `auth.uid()` itself, so it can only ever wipe the caller's own row set
-- — no one can use it to scrub somebody else's likes.

create or replace function public.delete_my_received_likes()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_count integer := 0;
begin
  if v_uid is null then
    return 0;
  end if;
  with deleted as (
    delete from public.likes
      where liked = v_uid
      returning 1
  )
  select count(*) into v_count from deleted;
  return v_count;
end;
$$;

revoke all on function public.delete_my_received_likes() from public;
grant execute on function public.delete_my_received_likes() to authenticated;
