import { cp, mkdir, rm, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const landingDir = resolve(root, "landing");
const distDir = resolve(root, "dist");

const config = {
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? process.env.SUPABASE_URL ?? "",
  supabaseAnonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? process.env.SUPABASE_ANON_KEY ?? "",
};

await rm(distDir, { recursive: true, force: true });
await mkdir(distDir, { recursive: true });
await cp(landingDir, distDir, { recursive: true });
await writeFile(
  resolve(distDir, "config.js"),
  `window.ELEPH_CONFIG = ${JSON.stringify(config, null, 2)};\n`,
);
