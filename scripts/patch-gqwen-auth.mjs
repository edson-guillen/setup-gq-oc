#!/usr/bin/env node

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const bunInstall = process.env.BUN_INSTALL || path.join(os.homedir(), ".bun");
const targets = [
  path.join(bunInstall, "install", "global", "node_modules", "gqwen-auth", "dist", "gqwen"),
  path.join(
    bunInstall,
    "install",
    "global",
    "node_modules",
    "gqwen-auth",
    "node_modules",
    "gqwen-auth",
    "dist",
    "gqwen",
  ),
];

const patchMarker = "pendingSessionsGcTimer.unref?.();";
const patchPattern =
  /var pendingSessions = new Map;\r?\nsetInterval\(\(\) => \{\r?\n([\s\S]*?)\r?\n\}, 10 \* 60 \* 1000\);/;

let discovered = 0;
let patched = 0;
let alreadyPatched = 0;

for (const target of targets) {
  if (!fs.existsSync(target)) {
    continue;
  }

  discovered += 1;

  const original = fs.readFileSync(target, "utf8");
  if (original.includes(patchMarker)) {
    alreadyPatched += 1;
    console.log(`[ok] already patched: ${target}`);
    continue;
  }

  const newline = original.includes("\r\n") ? "\r\n" : "\n";
  const next = original.replace(patchPattern, (_match, body) =>
    [
      "var pendingSessions = new Map;",
      "var pendingSessionsGcTimer = setInterval(() => {",
      body,
      "}, 10 * 60 * 1000);",
      "pendingSessionsGcTimer.unref?.();",
    ].join(newline),
  );

  if (next === original) {
    console.error(`[err] patch target not found: ${target}`);
    continue;
  }

  fs.writeFileSync(target, next, "utf8");
  patched += 1;
  console.log(`[ok] patched: ${target}`);
}

if (discovered === 0) {
  console.error("[err] gqwen-auth not found under Bun global directory.");
  process.exit(1);
}

if (patched === 0 && alreadyPatched === 0) {
  console.error("[err] gqwen-auth found, but patch could not be applied.");
  process.exit(1);
}

console.log(`[done] gqwen-auth patch ready (${patched} changed, ${alreadyPatched} already patched).`);
