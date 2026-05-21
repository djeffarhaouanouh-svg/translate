import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Swayco — Admin",
  description: "Tableau de bord administrateur Swayco",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="fr" className="h-full">
      <body className="min-h-full">{children}</body>
    </html>
  );
}
