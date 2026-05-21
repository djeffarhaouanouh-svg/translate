import { getRetention } from "@/lib/metrics";
import { SectionHeader, EmptyState } from "@/components/section";
import { KpiCard } from "@/components/kpi-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { AreaSeries } from "@/components/charts/series";
import { fmtInt, fmtPct, shortDay } from "@/lib/format";

export default async function RetentionPage() {
  const ret = await getRetention(30);
  const cell = (v: number | null) => (v === null ? "—" : fmtPct(v, 0));

  return (
    <>
      <SectionHeader
        title="Rétention"
        description="Cohortes journalières, rétention D1 / D7 / D30 et utilisateurs actifs."
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard
          label="Rétention D1"
          value={fmtPct(ret.overall.d1, 0)}
          sub="actif le lendemain"
        />
        <KpiCard label="Rétention D7" value={fmtPct(ret.overall.d7, 0)} />
        <KpiCard label="Rétention D30" value={fmtPct(ret.overall.d30, 0)} />
        <KpiCard
          label="Utilisateurs perdus"
          value={fmtInt(ret.lostUsers)}
          sub="inactifs > 30 j"
          tone={ret.lostUsers > 0 ? "warn" : "default"}
        />
      </div>

      <div className="mt-6">
        <Card>
          <CardHeader>
            <CardTitle>Utilisateurs actifs par jour (DAU) — 30 j</CardTitle>
          </CardHeader>
          <CardContent>
            <AreaSeries data={ret.dau} color="#34d399" />
          </CardContent>
        </Card>
      </div>

      <div className="mt-6">
        <Card>
          <CardHeader>
            <CardTitle>Cohortes — par jour de première ouverture</CardTitle>
          </CardHeader>
          <CardContent>
            {ret.cohorts.length === 0 ? (
              <EmptyState>Pas encore de données de cohorte</EmptyState>
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-xs uppercase tracking-wide text-zinc-500">
                    <th className="pb-2 font-medium">Cohorte</th>
                    <th className="pb-2 text-right font-medium">Taille</th>
                    <th className="pb-2 text-right font-medium">D1</th>
                    <th className="pb-2 text-right font-medium">D7</th>
                    <th className="pb-2 text-right font-medium">D30</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-zinc-800">
                  {ret.cohorts.map((c) => (
                    <tr key={c.cohort}>
                      <td className="py-2 text-zinc-300">
                        {shortDay(c.cohort)}
                      </td>
                      <td className="py-2 text-right tabular-nums text-zinc-400">
                        {fmtInt(c.size)}
                      </td>
                      <td className="py-2 text-right tabular-nums text-zinc-300">
                        {cell(c.d1)}
                      </td>
                      <td className="py-2 text-right tabular-nums text-zinc-300">
                        {cell(c.d7)}
                      </td>
                      <td className="py-2 text-right tabular-nums text-zinc-300">
                        {cell(c.d30)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </CardContent>
        </Card>
      </div>

      <p className="mt-4 text-xs text-zinc-600">
        Rétention DN classique : l&apos;utilisateur compte s&apos;il a rouvert
        l&apos;app exactement J+N après sa première session. « — » = le jour
        n&apos;est pas encore atteint pour cette cohorte.
      </p>
    </>
  );
}
