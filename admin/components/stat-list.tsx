import { cn } from "@/lib/utils";

type Tone = "default" | "good" | "warn" | "bad" | "muted";

const TONE: Record<Tone, string> = {
  default: "text-zinc-200",
  good: "text-emerald-400",
  warn: "text-amber-400",
  bad: "text-rose-400",
  muted: "text-zinc-500",
};

/** Label / value rows separated by hairlines — used inside cards. */
export function StatList({
  items,
}: {
  items: { label: string; value: string; tone?: Tone }[];
}) {
  return (
    <ul className="divide-y divide-zinc-800">
      {items.map((it) => (
        <li
          key={it.label}
          className="flex items-center justify-between py-2.5 text-sm first:pt-0 last:pb-0"
        >
          <span className="text-zinc-400">{it.label}</span>
          <span
            className={cn(
              "font-medium tabular-nums",
              TONE[it.tone ?? "default"],
            )}
          >
            {it.value}
          </span>
        </li>
      ))}
    </ul>
  );
}
