import { cn } from "@/lib/utils";
import { fmtInt } from "@/lib/format";
import { EmptyState } from "./section";

type Item = { label: string; value: number; hint?: string };

/**
 * Pure-CSS ranked bar list (no Recharts) — used for language pairs,
 * countries and any "top N" breakdown.
 */
export function RankBars({
  items,
  color = "bg-indigo-500",
  empty = "Aucune donnée",
}: {
  items: Item[];
  color?: string;
  empty?: string;
}) {
  if (items.length === 0) return <EmptyState>{empty}</EmptyState>;
  const max = Math.max(1, ...items.map((i) => i.value));
  return (
    <div className="space-y-3">
      {items.map((it) => (
        <div key={it.label}>
          <div className="flex items-baseline justify-between gap-3 text-sm">
            <span className="truncate text-zinc-300">{it.label}</span>
            <span className="shrink-0 tabular-nums text-zinc-500">
              {it.hint ?? fmtInt(it.value)}
            </span>
          </div>
          <div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-zinc-800">
            <div
              className={cn("h-full rounded-full", color)}
              style={{ width: `${(it.value / max) * 100}%` }}
            />
          </div>
        </div>
      ))}
    </div>
  );
}
