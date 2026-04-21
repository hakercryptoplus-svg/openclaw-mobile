#!/usr/bin/env node
/**
 * OpenClaw Mobile config generator.
 * Reads SSH + Telegram settings from the environment and writes
 * ~/.openclaw/openclaw.json so that every agent session uses the
 * built-in `sandbox.backend = "ssh"` runtime to forward all bash/exec
 * to the user's remote SSH compute host.
 *
 * Secrets (private key, known_hosts, telegram token) are NOT inlined
 * into the config; they are referenced via `${ENV_VAR}` template
 * syntax that OpenClaw's secret loader resolves at runtime from the
 * shell env (populated by ~/.openclaw-mobile/env).
 */
import { existsSync, mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { randomBytes } from "node:crypto";

const stateDir = process.env.OPENCLAW_STATE_DIR ?? join(homedir(), ".openclaw");
const configPath =
  process.env.OPENCLAW_CONFIG_PATH ?? join(stateDir, "openclaw.json");
const devicesDir = join(stateDir, "devices");
mkdirSync(devicesDir, { recursive: true });

const sshTarget = process.env.OPENCLAW_SSH_TARGET;
if (!sshTarget) {
  console.error("[init-mobile] missing OPENCLAW_SSH_TARGET");
  process.exit(1);
}
if (!process.env.OPENCLAW_SSH_PRIVATE_KEY) {
  console.error("[init-mobile] missing OPENCLAW_SSH_PRIVATE_KEY");
  process.exit(1);
}

const remoteWorkspace =
  process.env.OPENCLAW_SSH_WORKSPACE_ROOT ?? "~/openclaw-workspace";

const telegramEnabled =
  process.env.OPENCLAW_DISABLE_TELEGRAM !== "1" &&
  Boolean(process.env.TELEGRAM_BOT_TOKEN);

const gatewayToken =
  process.env.OPENCLAW_GATEWAY_TOKEN ?? randomBytes(24).toString("hex");

const config = {
  gateway: {
    mode: "local",
    port: Number(process.env.OPENCLAW_GATEWAY_PORT ?? 5000),
    auth: { mode: "token", token: gatewayToken },
  },
  models: {
    providers: {
      "render-skywork": {
        baseUrl:
          process.env.RENDER_SKYWORK_BASE_URL ??
          "https://skywork-proxy.onrender.com/v1",
        apiKey:
          process.env.RENDER_SKYWORK_API_KEY ?? "${RENDER_SKYWORK_API_KEY}",
        api: "openai-completions",
        models: [
          { id: "claude-opus-4.6", name: "Claude Opus 4.6" },
          { id: "gemini-3.1-pro", name: "Gemini 3.1 Pro" },
          { id: "deepseek-r1", name: "DeepSeek R1" },
        ],
      },
    },
  },
  agents: {
    defaults: {
      model: process.env.OPENCLAW_DEFAULT_MODEL ?? "render-skywork/claude-opus-4.6",
      // The critical bit: every agent session, by default, uses the SSH
      // sandbox backend. All exec/bash/file ops are forwarded to the
      // remote compute host instead of running on the phone.
      sandbox: {
        mode: "all",
        backend: "ssh",
        scope: "shared",
        workspaceAccess: "rw",
        workspaceRoot: remoteWorkspace,
        ssh: {
          target: sshTarget,
          workspaceRoot: remoteWorkspace,
          strictHostKeyChecking: true,
          updateHostKeys: true,
          identityData: "${OPENCLAW_SSH_PRIVATE_KEY}",
          knownHostsData: "${OPENCLAW_SSH_KNOWN_HOSTS}",
        },
      },
    },
  },
  channels: {
    telegram: telegramEnabled
      ? {
          enabled: true,
          botToken: "${TELEGRAM_BOT_TOKEN}",
          allowFrom: process.env.TELEGRAM_ALLOW_CHAT
            ? [process.env.TELEGRAM_ALLOW_CHAT]
            : [],
          defaultTo: process.env.TELEGRAM_ALLOW_CHAT ?? undefined,
        }
      : { enabled: false },
  },
};

if (existsSync(configPath)) {
  const backup = `${configPath}.bak-${Date.now()}`;
  writeFileSync(backup, readFileSync(configPath));
  console.log(`[init-mobile] backed up existing config → ${backup}`);
}
writeFileSync(configPath, JSON.stringify(config, null, 2));
console.log(`[init-mobile] wrote ${configPath}`);

// Ensure devices files exist so the gateway can start without onboarding.
const pairedPath = join(devicesDir, "paired.json");
const pendingPath = join(devicesDir, "pending.json");
if (!existsSync(pairedPath)) writeFileSync(pairedPath, "{}\n");
if (!existsSync(pendingPath)) writeFileSync(pendingPath, "{}\n");

console.log(`[init-mobile] gateway token: ${gatewayToken}`);
console.log("[init-mobile] done");
