-- Mirror `auth.users.email` into `public.profiles.email` so the email is
-- visible from the Table Editor / SQL Editor without joining to auth.users.
--
-- PRIVACY NOTE: `public.profiles` is currently readable by everyone
-- (RLS policy `anon_read_profiles using (true)`). Adding the email here
-- means anyone with the anon key can scrape every email. Tighten the
-- policy or move the email behind a SECURITY DEFINER function / private
-- view if that's not what you want.

alter table public.profiles
  add column if not exists email text;

-- One-shot backfill for existing profiles.
update public.profiles p
   set email = u.email
  from auth.users u
 where p.id = u.id
   and (p.email is distinct from u.email);

-- ── Keep email in sync ──────────────────────────────────────────────────
-- 1. When auth.users is created or its email changes, push it down to the
--    matching profile (if one exists yet).
create or replace function public._sync_profile_email_from_auth()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
     set email = new.email
   where id = new.id;
  return new;
end;
$$;

drop trigger if exists sync_profile_email_ins on auth.users;
create trigger sync_profile_email_ins
  after insert on auth.users
  for each row execute function public._sync_profile_email_from_auth();

drop trigger if exists sync_profile_email_upd on auth.users;
create trigger sync_profile_email_upd
  after update of email on auth.users
  for each row execute function public._sync_profile_email_from_auth();

-- 2. When a profile row is inserted (the app creates it after sign-up),
--    pull the email from auth.users so we don't have to wait for the next
--    auth update to populate it.
create or replace function public._fill_profile_email_on_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.email is null then
    select u.email into new.email
      from auth.users u
     where u.id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists fill_profile_email_on_insert on public.profiles;
create trigger fill_profile_email_on_insert
  before insert on public.profiles
  for each row execute function public._fill_profile_email_on_insert();
