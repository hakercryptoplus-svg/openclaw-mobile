#!/data/data/com.termux/files/usr/bin/bash
# OpenClaw Mobile Port — Termux installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/hakercryptoplus-svg/openclaw-mobile/main/install-termux.sh | bash
set -euo pipefail

BOLD=$'\033[1m'
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
CYAN=$'\033[36m'
DIM=$'\033[2m'
NC=$'\033[0m'

say()  { printf '%s\n' "${CYAN}»${NC} $*"; }
ok()   { printf '%s\n' "${GREEN}✓${NC} $*"; }
warn() { printf '%s\n' "${YELLOW}!${NC} $*"; }
die()  { printf '%s\n' "${RED}✗${NC} $*" >&2; exit 1; }

REPO_URL="${OPENCLAW_MOBILE_REPO:-https://github.com/hakercryptoplus-svg/openclaw-mobile.git}"
UPSTREAM_NPM="${OPENCLAW_NPM_PACKAGE:-openclaw}"
PREFIX_BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
MOBILE_DIR="$HOME_DIR/.openclaw-mobile"
ENV_FILE="$MOBILE_DIR/env"
STATE_DIR="$HOME_DIR/.openclaw"
CONFIG_FILE="$STATE_DIR/openclaw.json"

is_termux() {
  [[ -n "${PREFIX:-}" && "$PREFIX" == *com.termux* ]] || command -v termux-info >/dev/null 2>&1
}

if ! is_termux; then
  warn "This installer targets Termux on Android."
  warn "Detected non-Termux environment. Continuing anyway, but expect issues."
fi

printf '\n%s\n' "${BOLD}🦞 OpenClaw Mobile — Termux installer${NC}"
printf '%s\n\n' "${DIM}phone hosts the gateway, ssh server runs the commands${NC}"

###############################################################################
# 1) Packages
###############################################################################
say "Installing Termux packages (nodejs, openssh, git, jq, curl)…"
if command -v pkg >/dev/null 2>&1; then
  pkg update -y >/dev/null
  pkg install -y nodejs openssh git jq curl >/dev/null
  ok "Packages installed."
else
  warn "pkg not found — assuming dependencies are present."
  for c in node ssh git jq curl; do command -v "$c" >/dev/null || die "Missing: $c"; done
fi

###############################################################################
# 2) Wake lock recommendation
###############################################################################
if ! command -v termux-wake-lock >/dev/null 2>&1; then
  warn "Termux:API not detected. Install it (F-Droid) and run 'termux-wake-lock' so OpenClaw stays alive in the background."
fi

###############################################################################
# 3) Prepare directories
###############################################################################
mkdir -p "$MOBILE_DIR" "$STATE_DIR"
chmod 700 "$MOBILE_DIR"
touch "$ENV_FILE"
chmod 600 "$ENV_FILE"

###############################################################################
# 4) SSH credentials wizard
###############################################################################
prompt() { local var="$1" msg="$2" def="${3:-}"; local val; printf '%s%s%s ' "${BOLD}" "$msg" "${NC}"; if [[ -n "$def" ]]; then printf '[%s] ' "$def"; fi; read -r val; printf -v "$var" '%s' "${val:-$def}"; }

upsert_env() {
  local key="$1" val="$2"
  local tmp="$ENV_FILE.tmp"
  grep -v "^export ${key}=" "$ENV_FILE" 2>/dev/null > "$tmp" || true
  printf 'export %s=%q\n' "$key" "$val" >> "$tmp"
  mv "$tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

# shellcheck disable=SC1090
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" || true

say "SSH compute host configuration"
echo "  Format: user@host:port  (port defaults to 22)"
prompt SSH_TARGET "  SSH target" "${OPENCLAW_SSH_TARGET:-}"
[[ -n "$SSH_TARGET" ]] || die "SSH target is required."
upsert_env OPENCLAW_SSH_TARGET "$SSH_TARGET"

# Private key
echo
say "SSH private key"
echo "  Options: (1) paste an existing key, (2) generate a new one for OpenClaw."
prompt KEY_CHOICE "  Choice [1/2]" "2"

if [[ "$KEY_CHOICE" == "1" ]]; then
  echo "  Paste the OpenSSH private key, then a single line containing only END:"
  KEY_TMP=$(mktemp)
  while IFS= read -r line; do
    [[ "$line" == "END" ]] && break
    printf '%s\n' "$line" >> "$KEY_TMP"
  done
  KEY_DATA="$(cat "$KEY_TMP")"
  shred -u "$KEY_TMP" 2>/dev/null || rm -f "$KEY_TMP"
  [[ -n "$KEY_DATA" ]] || die "Empty key."
else
  KEY_PATH="$MOBILE_DIR/id_ed25519"
  if [[ ! -f "$KEY_PATH" ]]; then
    say "Generating new ed25519 key at $KEY_PATH"
    ssh-keygen -t ed25519 -N "" -C "openclaw-mobile@$(date +%Y%m%d)" -f "$KEY_PATH" >/dev/null
  else
    ok "Reusing existing key at $KEY_PATH"
  fi
  KEY_DATA="$(cat "$KEY_PATH")"
  echo
  ok "Add this PUBLIC key to your SSH server's ~/.ssh/authorized_keys:"
  echo "${DIM}-----------------------------------------------------------------${NC}"
  cat "$KEY_PATH.pub"
  echo "${DIM}-----------------------------------------------------------------${NC}"
  prompt _ACK "  Press Enter once added" ""
fi
upsert_env OPENCLAW_SSH_PRIVATE_KEY "$KEY_DATA"

# Known hosts
echo
say "Verifying server host key (ssh-keyscan)…"
HOST_PART="${SSH_TARGET#*@}"
HOST_ONLY="${HOST_PART%%:*}"
PORT_PART="${HOST_PART##*:}"
[[ "$PORT_PART" == "$HOST_PART" ]] && PORT_PART="22"
KNOWN_HOSTS_DATA="$(ssh-keyscan -p "$PORT_PART" -T 10 "$HOST_ONLY" 2>/dev/null || true)"
if [[ -z "$KNOWN_HOSTS_DATA" ]]; then
  warn "Could not reach $HOST_ONLY:$PORT_PART for ssh-keyscan. Saving config anyway; OpenClaw will fail until reachable."
else
  ok "Captured host key for $HOST_ONLY"
fi
upsert_env OPENCLAW_SSH_KNOWN_HOSTS "$KNOWN_HOSTS_DATA"

# Workspace root on remote
prompt REMOTE_WS "  Remote workspace directory" "${OPENCLAW_SSH_WORKSPACE_ROOT:-/home/$(printf '%s' "$SSH_TARGET" | sed 's/@.*//')/openclaw-workspace}"
upsert_env OPENCLAW_SSH_WORKSPACE_ROOT "$REMOTE_WS"

###############################################################################
# 5) Telegram (optional)
###############################################################################
echo
say "Telegram bot (optional, leave empty to skip)"
prompt TG_TOKEN "  Bot token" "${TELEGRAM_BOT_TOKEN:-}"
if [[ -n "$TG_TOKEN" ]]; then
  prompt TG_CHAT "  Your Telegram chat ID (only this user will be allowed)" "${TELEGRAM_ALLOW_CHAT:-}"
  upsert_env TELEGRAM_BOT_TOKEN "$TG_TOKEN"
  upsert_env TELEGRAM_ALLOW_CHAT "$TG_CHAT"
  upsert_env OPENCLAW_DISABLE_TELEGRAM "0"
else
  upsert_env OPENCLAW_DISABLE_TELEGRAM "1"
fi

###############################################################################
# 6) Install OpenClaw + this repo's config layer
###############################################################################
echo
say "Cloning openclaw-mobile (config layer)…"
MOBILE_REPO_DIR="$MOBILE_DIR/repo"
if [[ -d "$MOBILE_REPO_DIR/.git" ]]; then
  git -C "$MOBILE_REPO_DIR" pull --ff-only >/dev/null
else
  rm -rf "$MOBILE_REPO_DIR"
  git clone --depth 1 "$REPO_URL" "$MOBILE_REPO_DIR" >/dev/null
fi
ok "openclaw-mobile cloned at $MOBILE_REPO_DIR"

say "Installing OpenClaw from npm (this can take a few minutes)…"
export SHARP_IGNORE_GLOBAL_LIBVIPS=1
npm install -g "$UPSTREAM_NPM" --no-audit --no-fund --silent || die "npm install failed. Re-run with: npm install -g $UPSTREAM_NPM"
ok "OpenClaw installed."

###############################################################################
# 7) Generate config
###############################################################################
say "Generating $CONFIG_FILE …"
# shellcheck disable=SC1090
source "$ENV_FILE"
node "$MOBILE_REPO_DIR/scripts/init-mobile-config.mjs"
ok "Config written."

###############################################################################
# 8) Launcher
###############################################################################
say "Installing 'openclaw-mobile' launcher…"
install -m 0755 "$MOBILE_REPO_DIR/bin/openclaw-mobile" "$PREFIX_BIN/openclaw-mobile"
ok "Launcher installed at $PREFIX_BIN/openclaw-mobile"

###############################################################################
# 9) Test SSH
###############################################################################
echo
say "Testing SSH connectivity…"
TMP_KEY="$(mktemp)"
chmod 600 "$TMP_KEY"
printf '%s\n' "$OPENCLAW_SSH_PRIVATE_KEY" > "$TMP_KEY"
TMP_KH="$(mktemp)"
printf '%s\n' "${OPENCLAW_SSH_KNOWN_HOSTS:-}" > "$TMP_KH"
SSH_USER_HOST="${SSH_TARGET%:*}"
SSH_PORT="${SSH_TARGET##*:}"; [[ "$SSH_PORT" == "$SSH_TARGET" ]] && SSH_PORT="22"
if ssh -i "$TMP_KEY" -o "UserKnownHostsFile=$TMP_KH" -o "StrictHostKeyChecking=yes" -o "ConnectTimeout=10" -p "$SSH_PORT" "$SSH_USER_HOST" "echo openclaw-ssh-ok && mkdir -p $(printf '%q' "$REMOTE_WS")" 2>/dev/null | grep -q openclaw-ssh-ok; then
  ok "SSH login works and remote workspace is ready."
else
  warn "SSH test failed. Fix authorized_keys / network and re-run installer."
fi
shred -u "$TMP_KEY" "$TMP_KH" 2>/dev/null || rm -f "$TMP_KEY" "$TMP_KH"

###############################################################################
# 10) Done
###############################################################################
echo
ok "${BOLD}Installation complete.${NC}"
echo
echo "  ${BOLD}Start:${NC}   openclaw-mobile start"
echo "  ${BOLD}Logs:${NC}    openclaw-mobile logs"
echo "  ${BOLD}Stop:${NC}    openclaw-mobile stop"
echo "  ${BOLD}Config:${NC}  openclaw-mobile config"
echo
echo "  Tip: run ${BOLD}termux-wake-lock${NC} so Android keeps OpenClaw alive."
echo
