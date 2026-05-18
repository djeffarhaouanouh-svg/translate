-- Stripe-side identifiers + the user's current tier on `profiles`.
-- The Stripe webhook handler updates these as checkout completes,
-- renewals fire, and cancellations happen.

alter table public.profiles
  add column if not exists stripe_customer_id text,
  add column if not exists stripe_subscription_id text,
  add column if not exists subscription_tier text;

-- Defensive in case CHECK was set previously.
do $$
begin
  alter table public.profiles
    add constraint profiles_subscription_tier_chk
      check (subscription_tier in ('free', 'pro', 'ultra'));
exception when duplicate_object then null;
end$$;

update public.profiles
   set subscription_tier = 'free'
 where subscription_tier is null;

create index if not exists profiles_stripe_subscription_idx
  on public.profiles (stripe_subscription_id);
