import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

/**
 * Next.js 16 renamed the `middleware` convention to `proxy` (Node.js
 * runtime). Its only job here: keep the Supabase auth session fresh by
 * round-tripping the cookies on every request. The actual access gate
 * (signed in + is_admin) lives in app/(dashboard)/layout.tsx — see the
 * Next.js data-security guide: never rely on the proxy alone for auth.
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  // Not configured yet (fresh clone, no .env.local) — don't 500 every
  // route; let the page render and surface the missing-env error itself.
  if (!url || !anonKey) return response;

  const supabase = createServerClient(
    url,
    anonKey,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          for (const { name, value } of cookiesToSet) {
            request.cookies.set(name, value);
          }
          response = NextResponse.next({ request });
          for (const { name, value, options } of cookiesToSet) {
            response.cookies.set(name, value, options);
          }
        },
      },
    },
  );

  // Touching getUser() triggers a token refresh when needed.
  await supabase.auth.getUser();
  return response;
}

export const config = {
  // Run on every route except static assets.
  matcher: ["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|ico)$).*)"],
};
