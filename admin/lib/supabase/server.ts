import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

/**
 * Supabase client bound to the request cookies — used to read the
 * signed-in admin's session in Server Components / the dashboard layout.
 * Uses the public anon key; it only ever reads auth state, never data
 * (data goes through the service client).
 */
export async function createSupabaseServerClient() {
  const cookieStore = await cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            for (const { name, value, options } of cookiesToSet) {
              cookieStore.set(name, value, options);
            }
          } catch {
            // Cookie writes are not allowed from a Server Component —
            // the proxy (proxy.ts) is what refreshes the session.
          }
        },
      },
    },
  );
}
