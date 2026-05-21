# Swayco Admin

Off-site administration dashboard for the Swayco app — built with
Next.js 16 (App Router), Tailwind v4, Recharts and Supabase.

It reads the `analytics_events` table (populated by the app + backend,
see migration `0017` and `backend/analytics.js`) plus the existing
`profiles` / `friendships` / `messages` / `live_lobby` tables, and never
writes anything.

## Sections

- **Vue d'ensemble** — headline KPIs, call & signup trends.
- **Live** — calls in progress, users on a call, lobby queue, countries
  & languages active right now (auto-refresh 20 s).
- **Traduction** — pipeline latency, error rate, language pairs.
- **Social** — friends, conversations, recurring users.
- **Rétention** — D1 / D7 / D30, DAU, daily cohorts.
- **Monétisation** — MRR, infra cost, margin, subscription mix.

## Setup

```bash
cd admin
cp env.example .env.local      # then fill in the values
npm install
npm run dev                    # http://localhost:3000
```

### Environment

See `env.example`. You need the Supabase URL + anon key + **service-role
key** (the dashboard reads the RLS-locked analytics table with it). The
cost rates default to `0` — fill them from the current OpenAI / LiveKit
pricing pages to light up the Monétisation figures.

## Access control

Auth is Supabase Auth against the same project. A user can sign in only
if their `profiles` row has `is_admin = true`:

```sql
update public.profiles set is_admin = true where id = '<your-user-uuid>';
```

The check runs both at login and in `app/(dashboard)/layout.tsx`.

## Deploy

Designed for Vercel (separate project from the app, e.g.
`admin.swayco.fr`). Set the same environment variables in the Vercel
project. `proxy.ts` (Next 16's renamed middleware) keeps the Supabase
session fresh.

## Notes / next steps

- Aggregations run in JS over bounded query windows — fine while the
  app is young. Once `analytics_events` gets large, move the heavy
  aggregates (`getRetention`, `getCountries`, …) to SQL views / RPCs.
- Revenue is derived from subscription tiers on `profiles`. For real
  collected revenue, wire in the Stripe API.
