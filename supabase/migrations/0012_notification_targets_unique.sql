-- The partial unique indexes from migration 0011 don't satisfy
-- `ON CONFLICT (...) DO UPDATE`. Postgres requires the inference to
-- match a full unique constraint / index — `WHERE platform = 'web'`
-- excludes them.
--
-- Swap them for plain UNIQUE constraints. NULL handling is fine:
-- Postgres treats NULLs as distinct, so two native rows with NULL
-- `endpoint` (or two web rows with NULL `fcm_token`) never collide.

drop index if exists public.notification_targets_web_unique;
drop index if exists public.notification_targets_native_unique;

do $$
begin
  alter table public.notification_targets
    add constraint notification_targets_user_endpoint_key
      unique (user_id, endpoint);
exception when duplicate_object then null;
end$$;

do $$
begin
  alter table public.notification_targets
    add constraint notification_targets_user_fcm_key
      unique (user_id, fcm_token);
exception when duplicate_object then null;
end$$;
