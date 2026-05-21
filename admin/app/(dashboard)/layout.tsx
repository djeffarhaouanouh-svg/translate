import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import { Sidebar } from "@/components/sidebar";

// Every dashboard page reads live data — never statically cache them.
export const dynamic = "force-dynamic";

/**
 * Access gate for the whole dashboard: must be signed in AND flagged
 * `profiles.is_admin`. This server-side check is the real boundary —
 * the proxy only refreshes the session (see proxy.ts).
 */
export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  let isAdmin = false;
  try {
    const svc = createSupabaseServiceClient();
    const { data } = await svc
      .from("profiles")
      .select("is_admin")
      .eq("id", user.id)
      .maybeSingle();
    isAdmin = Boolean(data?.is_admin);
  } catch {
    isAdmin = false;
  }
  if (!isAdmin) redirect("/login");

  return (
    <div className="flex h-screen overflow-hidden">
      <Sidebar adminEmail={user.email ?? ""} />
      <main className="flex-1 overflow-y-auto">
        <div className="mx-auto max-w-6xl px-8 py-8">{children}</div>
      </main>
    </div>
  );
}
