-- Returns the peer ids of every accepted friendship for `p_user_id`, in the
-- requested direction. Same rationale as `friendship_counts` (migration
-- 0003): a restrictive RLS on `friendships` was hiding rows that didn't
-- involve the caller, so the followers / following lists came back
-- incomplete when viewing one's own profile from an account that only had
-- visibility into a subset of rows.
--
-- This SECURITY DEFINER function bypasses RLS but only exposes peer ids,
-- which `public.profiles` already serves to everyone (RLS using true), so
-- no extra information leaks.

create or replace function public.friendship_accepted_peers(
  p_user_id   uuid,
  p_direction text
)
returns table(peer_id uuid)
language sql
security definer
set search_path = public
as $$
  select case
           when p_direction = 'followers' then requester
           else addressee
         end as peer_id
    from public.friendships
   where status = 'accepted'
     and (
       (p_direction = 'followers' and addressee = p_user_id)
       or
       (p_direction = 'following' and requester = p_user_id)
     );
$$;

revoke all on function public.friendship_accepted_peers(uuid, text) from public;
grant execute on function public.friendship_accepted_peers(uuid, text)
  to anon, authenticated;
