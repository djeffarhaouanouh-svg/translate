-- Public counts for the profile screen (abonnés / abonnements).
--
-- Why a SECURITY DEFINER function: the deployed RLS on `friendships` may
-- restrict SELECT to rows involving the caller, which makes a direct
-- `count(*)` from the client return wrong numbers when looking at someone
-- else's profile (caller only sees the rows they're part of). This function
-- runs with the table owner's privileges and bypasses RLS, returning just
-- the aggregate counts — no row data leaks.

create or replace function public.friendship_counts(p_user_id uuid)
returns table(followers int, following int)
language sql
security definer
set search_path = public
as $$
  select
    (select count(*)::int
       from public.friendships
       where addressee = p_user_id and status = 'accepted') as followers,
    (select count(*)::int
       from public.friendships
       where requester = p_user_id and status = 'accepted') as following;
$$;

revoke all on function public.friendship_counts(uuid) from public;
grant execute on function public.friendship_counts(uuid) to anon, authenticated;
