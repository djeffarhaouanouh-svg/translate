import type { NextConfig } from "next";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";

const nextConfig: NextConfig = {
  // This app lives inside the Swayco monorepo, which has its own
  // lockfile one level up. Pin the Turbopack root to admin/ so it does
  // not infer the parent directory.
  turbopack: {
    root: dirname(fileURLToPath(import.meta.url)),
  },
};

export default nextConfig;
