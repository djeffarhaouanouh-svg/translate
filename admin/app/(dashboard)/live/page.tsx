import { getLiveSnapshot } from "@/lib/metrics";
import { SectionHeader, EmptyState } from "@/components/section";
import { KpiCard } from "@/components/kpi-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { AutoRefresh } from "@/components/auto-refresh";
import { countryName, flag, fmtInt } from "@/lib/format";

export default async function LivePage() {
  const live = await getLiveSnapshot();

  return (
    <>
      <AutoRefresh seconds={20} />
      <SectionHeader
        title="Live"
        description="Photo de l'activité en direct — rafraîchie toutes les 20 s."
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Appels en cours"
          value={fmtInt(live.liveCalls)}
          tone={live.liveCalls > 0 ? "good" : "default"}
        />
        <KpiCard
          label="Utilisateurs en appel"
          value={fmtInt(live.liveUsers)}
          tone={live.liveUsers > 0 ? "good" : "default"}
        />
        <KpiCard
          label="En file d'attente"
          value={fmtInt(live.waitingLobby)}
          sub="lobby live"
        />
        <KpiCard
          label="Pays connectés"
          value={fmtInt(live.countries.length)}
        />
      </div>

      <div className="mt-6 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Pays en appel</CardTitle>
          </CardHeader>
          <CardContent>
            {live.countries.length === 0 ? (
              <EmptyState>Aucun pays actif</EmptyState>
            ) : (
              <div className="flex flex-wrap gap-2">
                {live.countries.map((c) => (
                  <span
                    key={c}
                    className="rounded-md border border-zinc-800 bg-zinc-800/50 px-2.5 py-1 text-sm text-zinc-300"
                  >
                    {flag(c)} {countryName(c)}
                  </span>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Langues utilisées</CardTitle>
          </CardHeader>
          <CardContent>
            {live.languages.length === 0 ? (
              <EmptyState>Aucune langue active</EmptyState>
            ) : (
              <div className="flex flex-wrap gap-2">
                {live.languages.map((l) => (
                  <span
                    key={l}
                    className="rounded-md border border-zinc-800 bg-zinc-800/50 px-2.5 py-1 text-sm uppercase text-zinc-300"
                  >
                    {l}
                  </span>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      <p className="mt-4 text-xs text-zinc-600">
        Un appel est « en cours » s&apos;il a un évènement{" "}
        <code className="text-zinc-500">call_started</code> sans{" "}
        <code className="text-zinc-500">call_ended</code> dans les 6 dernières
        heures.
      </p>
    </>
  );
}
