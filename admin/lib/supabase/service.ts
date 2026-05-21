import { createClient } from "@supabase/supabase-js";

/**
 * Service-role Supabase client — bypasses RLS, so it can read the
 * RLS-locked `analytics_events` table and aggregate across every user.
 *
 * SERVER-ONLY. The key lives in `SUPABASE_SERVICE_ROLE_KEY` (note: no
 * `NEXT_PUBLIC_` prefix), so Next.js never bundles it into client code.
 * Import this file only from Server Components / Route Handlers — never
 * from a `"use client"` module.
 */
export function createSupabaseServiceClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new Error(
      "Supabase service env missing — set NEXT_PUBLIC_SUPABASE_URL and " +
        "SUPABASE_SERVICE_ROLE_KEY in admin/.env.local",
    );
  }
  return createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
