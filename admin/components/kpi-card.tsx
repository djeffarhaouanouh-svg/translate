import { cn } from "@/lib/utils";

type Tone = "default" | "good" | "warn" | "bad";

const TONE: Record<Tone, string> = {
  default: "text-zinc-50",
  good: "text-emerald-400",
  warn: "text-amber-400",
  bad: "text-rose-400",
};

/** A single headline metric tile. */
export function KpiCard({
  label,
  value,
  sub,
  tone = "default",
}: {
  label: string;
  value: string;
  sub?: string;
  tone?: Tone;
}) {
  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-900/60 p-5">
      <div className="text-xs font-medium uppercase tracking-wide text-zinc-500">
        {label}
      </div>
      <div className={cn("mt-2 text-3xl font-semibold tabular-nums", TONE[tone])}>
        {value}
      </div>
      {sub ? <div className="mt-1 text-sm text-zinc-400">{sub}</div> : null}
    </div>
  );
}
