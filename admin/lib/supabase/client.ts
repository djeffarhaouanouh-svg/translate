import { createBrowserClient } from "@supabase/ssr";

/**
 * Supabase client for the browser — used only by the login page to call
 * `signInWithPassword` / `signOut`. Public anon key, safe to ship.
 */
export function createSupabaseBrowserClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
