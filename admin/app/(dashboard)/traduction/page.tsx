import {
  getLanguagePairs,
  getLatencySeries,
  getTranslationStats,
} from "@/lib/metrics";
import { SectionHeader } from "@/components/section";
import { KpiCard } from "@/components/kpi-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { AreaSeries } from "@/components/charts/series";
import { RankBars } from "@/components/rank-bars";
import { StatList } from "@/components/stat-list";
import { fmtInt, fmtLatency, fmtPct } from "@/lib/format";

export default async function TraductionPage() {
  const [stats, latency, pairs] = await Promise.all([
    getTranslationStats(7),
    getLatencySeries(14),
    getLanguagePairs(30),
  ]);

  return (
    <>
      <SectionHeader
        title="Traduction"
        description="Latence, fiabilité et volume du pipeline OpenAI Realtime — fenêtre 7 j."
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Latence moyenne"
          value={fmtLatency(stats.avgLatency)}
          sub={`${fmtInt(stats.latencySamples)} mesures`}
        />
        <KpiCard label="Latence p95" value={fmtLatency(stats.p95Latency)} />
        <KpiCard
          label="Sessions OpenAI"
          value={fmtInt(stats.sessions)}
          sub="7 j"
        />
        <KpiCard
          label="Taux d'erreur"
          value={fmtPct(stats.errorRate, 1)}
          tone={
            stats.errorRate > 0.05
              ? "bad"
              : stats.errorRate > 0
                ? "warn"
                : "good"
          }
        />
      </div>

      <div className="mt-6 grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>
              Latence de mise en route — moyenne par jour (14 j)
            </CardTitle>
          </CardHeader>
          <CardContent>
            <AreaSeries data={latency} color="#22d3ee" unit="ms" />
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Fiabilité — 7 j</CardTitle>
          </CardHeader>
          <CardContent>
            <StatList
              items={[
                {
                  label: "Erreurs pipeline",
                  value: fmtInt(stats.errors),
                  tone: stats.errors > 0 ? "bad" : "default",
                },
                {
                  label: "Sessions échouées",
                  value: fmtInt(stats.sessionFails),
                  tone: stats.sessionFails > 0 ? "bad" : "default",
                },
                {
                  label: "Connexions appel échouées",
                  value: fmtInt(stats.callFails),
                  tone: stats.callFails > 0 ? "warn" : "default",
                },
                {
                  label: "Traductions texte",
                  value: fmtInt(stats.textTranslations),
                  tone: "muted",
                },
              ]}
            />
          </CardContent>
        </Card>
      </div>

      <div className="mt-6">
        <Card>
          <CardHeader>
            <CardTitle>Couples de langues traduits — 30 j</CardTitle>
          </CardHeader>
          <CardContent>
            <RankBars
              items={pairs}
              color="bg-cyan-500"
              empty="Aucun appel traduit pour l'instant"
            />
          </CardContent>
        </Card>
      </div>
    </>
  );
}
