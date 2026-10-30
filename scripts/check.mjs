import { readdir } from "node:fs/promises";
import path from "node:path";
import { spawnSync } from "node:child_process";

const root = path.resolve(import.meta.dirname, "..");
function run(bin, args) {
  const result = spawnSync(bin, args, { cwd: root, stdio: "inherit" });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
async function check(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if ([".git", "node_modules"].includes(entry.name)) continue;
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) await check(file);
    else if (/\.(mjs|ts)$/.test(file)) run(process.execPath, ["--check", file]);
    else if (file.endsWith(".lua")) run("luajit", ["-b", file, "/dev/null"]);
    else if (file.endsWith(".sh")) { run("sh", ["-n", file]); run("shellcheck", [file]); }
  }
}
await check(root);
console.log("JavaScript/TypeScript, Lua, and shell checks passed.");
