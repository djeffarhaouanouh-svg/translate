"use client";

import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { shortDay } from "@/lib/format";

export type SeriesPoint = { day: string; value: number };

/* eslint-disable @typescript-eslint/no-explicit-any */
function DarkTooltip({
  active,
  payload,
  label,
  unit,
}: any) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-2 text-xs shadow-xl">
      <div className="text-zinc-400">{shortDay(String(label))}</div>
      <div className="mt-0.5 font-semibold tabular-nums text-zinc-100">
        {payload[0].value}
        {unit ? ` ${unit}` : ""}
      </div>
    </div>
  );
}
/* eslint-enable @typescript-eslint/no-explicit-any */

const AXIS = {
  stroke: "#52525b",
  fontSize: 11,
  tickLine: false,
  axisLine: false,
} as const;

/** Daily bar chart — call volume, new users… */
export function BarSeries({
  data,
  color = "#6366f1",
  unit,
}: {
  data: SeriesPoint[];
  color?: string;
  unit?: string;
}) {
  return (
    <ResponsiveContainer width="100%" height={240}>
      <BarChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -18 }}>
        <CartesianGrid strokeDasharray="3 3" stroke="#27272a" vertical={false} />
        <XAxis
          dataKey="day"
          tickFormatter={shortDay}
          minTickGap={24}
          {...AXIS}
        />
        <YAxis allowDecimals={false} width={40} {...AXIS} />
        <Tooltip
          cursor={{ fill: "#ffffff0a" }}
          content={<DarkTooltip unit={unit} />}
        />
        <Bar dataKey="value" fill={color} radius={[4, 4, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  );
}

/** Daily area chart — latency, DAU… */
export function AreaSeries({
  data,
  color = "#22d3ee",
  unit,
}: {
  data: SeriesPoint[];
  color?: string;
  unit?: string;
}) {
  return (
    <ResponsiveContainer width="100%" height={240}>
      <AreaChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -18 }}>
        <defs>
          <linearGradient id={`g-${color}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity={0.35} />
            <stop offset="100%" stopColor={color} stopOpacity={0} />
          </linearGradient>
        </defs>
        <CartesianGrid strokeDasharray="3 3" stroke="#27272a" vertical={false} />
        <XAxis
          dataKey="day"
          tickFormatter={shortDay}
          minTickGap={24}
          {...AXIS}
        />
        <YAxis allowDecimals={false} width={40} {...AXIS} />
        <Tooltip content={<DarkTooltip unit={unit} />} />
        <Area
          type="monotone"
          dataKey="value"
          stroke={color}
          strokeWidth={2}
          fill={`url(#g-${color})`}
        />
      </AreaChart>
    </ResponsiveContainer>
  );
}
