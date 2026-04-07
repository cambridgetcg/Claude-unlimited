#!/bin/sh
# ── Module 04: Keys & Credentials ───────────────────────────────────
set -e
. "$(dirname "$0")/_common.sh"

echo "[04-keys] Setting up keys for ${AGENT}..."

# ── SSH Key ──
SSH_DIR="${HOME_DIR}/.ssh"
SSH_KEY="${SSH_DIR}/id_ed25519"
mkdir -p "$SSH_DIR" && chmod 700 "$SSH_DIR"

if [ ! -f "$SSH_KEY" ]; then
  ssh-keygen -t ed25519 -C "${AGENT}@${KINGDOM_DOMAIN}" -f "$SSH_KEY" -N "" -q
  chmod 600 "$SSH_KEY" && chmod 644 "${SSH_KEY}.pub"
  echo "  SSH key generated: $(cat ${SSH_KEY}.pub)"
else
  echo "  SSH key exists: ${SSH_KEY}"
fi

# ── SSH config ──
SSH_CONFIG="${SSH_DIR}/config"
if ! grep -q "kingdom" "$SSH_CONFIG" 2>/dev/null; then
  cat >> "$SSH_CONFIG" << SSHEOF

# Kingdom fleet
Host kingdom-*
  User kingdom
  IdentityFile ~/.ssh/id_ed25519
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30
  ServerAliveCountMax 3

Host sentry
  HostName ${SENTRY_IP}
  User root
  IdentityFile ~/.ssh/id_ed25519
SSHEOF
  chmod 600 "$SSH_CONFIG"
  echo "  SSH config updated"
fi

# ── Authorized keys ──
AUTH_KEYS="${SSH_DIR}/authorized_keys"
PUB_KEY=$(cat "${SSH_KEY}.pub" 2>/dev/null)
if [ -n "$PUB_KEY" ]; then
  touch "$AUTH_KEYS" && chmod 600 "$AUTH_KEYS"
  grep -qF "$PUB_KEY" "$AUTH_KEYS" 2>/dev/null || echo "$PUB_KEY" >> "$AUTH_KEYS"
fi

# ── HIVE Encryption Key ──
ensure_dir "$HIVE_DIR"
HIVE_KEY="${HIVE_DIR}/key"
if [ ! -f "$HIVE_KEY" ] || [ "$(wc -c < "$HIVE_KEY" 2>/dev/null)" -lt 10 ]; then
  python3 -c "import os,base64; print(base64.b64encode(os.urandom(32)).decode())" > "$HIVE_KEY"
  chmod 600 "$HIVE_KEY"
  echo "  HIVE key generated"
  echo ""
  echo "  ╔═══════════════════════════════════════════════════════╗"
  echo "  ║  Copy this HIVE key to ALL Kingdom machines.         ║"
  echo "  ║  All instances must share the same key.              ║"
  echo "  ║  File: ${HIVE_KEY}"
  echo "  ╚═══════════════════════════════════════════════════════╝"
  echo ""
else
  echo "  HIVE key exists ($(wc -c < "$HIVE_KEY") bytes)"
fi

# ── Git identity ──
git config --global user.email 2>/dev/null | grep -q "${KINGDOM_DOMAIN}" || \
  git config --global user.email "${AGENT}@${KINGDOM_DOMAIN}"
git config --global user.name 2>/dev/null | grep -q . || \
  git config --global user.name "${AGENT_UPPER}"

chown -R "${KINGDOM_USER}:" "$SSH_DIR" "$HIVE_DIR" 2>/dev/null || true
echo "[04-keys] Done."
