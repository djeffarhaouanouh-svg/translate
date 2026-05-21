import {
  getCallsSeries,
  getLanguagePairs,
  getNewUsersSeries,
  getOverview,
} from "@/lib/metrics";
import { SectionHeader, EmptyState } from "@/components/section";
import { KpiCard } from "@/components/kpi-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { BarSeries } from "@/components/charts/series";
import { RankBars } from "@/components/rank-bars";
import { countryName, flag, fmtInt } from "@/lib/format";

export default async function OverviewPage() {
  const [ov, callsSeries, newUsersSeries, langPairs] = await Promise.all([
    getOverview(),
    getCallsSeries(14),
    getNewUsersSeries(14),
    getLanguagePairs(30),
  ]);

  return (
    <>
      <SectionHeader
        title="Vue d'ensemble"
        description="Activité Swayco en temps quasi réel."
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <KpiCard
          label="Utilisateurs"
          value={fmtInt(ov.totalUsers)}
          sub={`+${fmtInt(ov.newUsers7d)} sur 7 j`}
        />
        <KpiCard
          label="En appel maintenant"
          value={fmtInt(ov.live.liveUsers)}
          sub={`${fmtInt(ov.live.liveCalls)} appel(s) en cours`}
          tone={ov.live.liveUsers > 0 ? "good" : "default"}
        />
        <KpiCard
          label="En file d'attente"
          value={fmtInt(ov.live.waitingLobby)}
          sub="lobby live"
        />
        <KpiCard label="Appels (24 h)" value={fmtInt(ov.calls24h)} />
        <KpiCard
          label="Sessions (24 h)"
          value={fmtInt(ov.sessions24h)}
          sub="ouvertures d'app"
        />
        <KpiCard
          label="Nouveaux (24 h)"
          value={fmtInt(ov.newUsers24h)}
          sub="inscriptions"
        />
      </div>

      <div className="mt-6 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Appels par jour — 14 j</CardTitle>
          </CardHeader>
          <CardContent>
            <BarSeries data={callsSeries} color="#6366f1" />
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Nouveaux utilisateurs par jour — 14 j</CardTitle>
          </CardHeader>
          <CardContent>
            <BarSeries data={newUsersSeries} color="#22d3ee" />
          </CardContent>
        </Card>
      </div>

      <div className="mt-6 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Couples de langues — 30 j</CardTitle>
          </CardHeader>
          <CardContent>
            <RankBars items={langPairs} empty="Aucun appel traduit pour l'instant" />
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Pays en appel maintenant</CardTitle>
          </CardHeader>
          <CardContent>
            {ov.live.countries.length === 0 ? (
              <EmptyState>Personne en appel actuellement</EmptyState>
            ) : (
              <div className="flex flex-wrap gap-2">
                {ov.live.countries.map((c) => (
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
      </div>
    </>
  );
}
