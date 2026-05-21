/** Page title + one-line description, used at the top of every section. */
export function SectionHeader({
  title,
  description,
}: {
  title: string;
  description?: string;
}) {
  return (
    <div className="mb-6">
      <h1 className="text-xl font-semibold text-zinc-50">{title}</h1>
      {description ? (
        <p className="mt-1 text-sm text-zinc-400">{description}</p>
      ) : null}
    </div>
  );
}

/** Placeholder shown inside a card when a query returned nothing yet. */
export function EmptyState({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-center justify-center rounded-lg border border-dashed border-zinc-800 py-10 text-sm text-zinc-500">
      {children}
    </div>
  );
}
