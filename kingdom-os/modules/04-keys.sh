#!/bin/sh
# ── Module 04: Keys & Credentials ───────────────────────────────────
# Generates SSH keys, HIVE encryption key, and configures git identity.
# Does NOT handle Zerone keys — that requires the chain binary.

set -e

AGENT="${AGENT:-alpha}"
KINGDOM_USER="${KINGDOM_USER:-kingdom}"
HOME_DIR=$(eval echo "~${KINGDOM_USER}")
LOVE_DIR="${HOME_DIR}/Love"
DOMAIN="ai-love.cc"

echo "[04-keys] Setting up keys for ${AGENT}..."

# ── SSH Key ──
SSH_DIR="${HOME_DIR}/.ssh"
SSH_KEY="${SSH_DIR}/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
  echo "  Generating Ed25519 SSH key..."
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  ssh-keygen -t ed25519 -C "${AGENT}@${DOMAIN}" -f "$SSH_KEY" -N "" -q
  chmod 600 "$SSH_KEY"
  chmod 644 "${SSH_KEY}.pub"
  echo "  SSH key: ${SSH_KEY}"
  echo "  Public:  $(cat ${SSH_KEY}.pub)"
else
  echo "  SSH key exists: ${SSH_KEY}"
fi

# ── SSH config for fleet ──
SSH_CONFIG="${SSH_DIR}/config"
if [ ! -f "$SSH_CONFIG" ] || ! grep -q "kingdom" "$SSH_CONFIG" 2>/dev/null; then
  cat >> "$SSH_CONFIG" << 'SSHEOF'

# Kingdom fleet defaults
Host kingdom-*
  User kingdom
  IdentityFile ~/.ssh/id_ed25519
  StrictHostKeyChecking accept-new
  ServerAliveInterval 30
  ServerAliveCountMax 3

# Sentry (HIVE relay)
Host sentry
  HostName 135.181.28.252
  User root
  IdentityFile ~/.ssh/id_ed25519
SSHEOF
  chmod 600 "$SSH_CONFIG"
  echo "  SSH config updated with Kingdom fleet hosts"
fi

# ── Authorized keys — add own pubkey ──
AUTH_KEYS="${SSH_DIR}/authorized_keys"
PUB_KEY=$(cat "${SSH_KEY}.pub" 2>/dev/null)
if [ -n "$PUB_KEY" ]; then
  touch "$AUTH_KEYS"
  chmod 600 "$AUTH_KEYS"
  if ! grep -qF "$PUB_KEY" "$AUTH_KEYS" 2>/dev/null; then
    echo "$PUB_KEY" >> "$AUTH_KEYS"
  fi
fi

# ── HIVE Encryption Key ──
HIVE_DIR="${HOME_DIR}/.love/hive"
HIVE_KEY="${HIVE_DIR}/key"
mkdir -p "$HIVE_DIR"
if [ ! -f "$HIVE_KEY" ] || [ "$(wc -c < "$HIVE_KEY" 2>/dev/null)" -lt 10 ]; then
  echo "  Generating HIVE encryption key (NaCl XSalsa20-Poly1305)..."
  python3 -c "
import os, base64
key = os.urandom(32)
print(base64.b64encode(key).decode())
" > "$HIVE_KEY"
  chmod 600 "$HIVE_KEY"
  echo "  HIVE key written: ${HIVE_KEY}"
  echo ""
  echo "  ╔═══════════════════════════════════════════════════════════╗"
  echo "  ║  IMPORTANT: Copy this HIVE key to ALL Kingdom machines.  ║"
  echo "  ║  All instances must share the same key for HIVE to work. ║"
  echo "  ║  File: ${HIVE_KEY}"
  echo "  ╚═══════════════════════════════════════════════════════════╝"
  echo ""
else
  echo "  HIVE key exists: ${HIVE_KEY} ($(wc -c < "$HIVE_KEY") bytes)"
fi

# ── Git identity ──
AGENT_UPPER=$(echo "$AGENT" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
CURRENT_EMAIL=$(git config --global user.email 2>/dev/null || echo "")
if [ -z "$CURRENT_EMAIL" ] || echo "$CURRENT_EMAIL" | grep -qv "${DOMAIN}"; then
  git config --global user.email "${AGENT}@${DOMAIN}"
  echo "  Git email: ${AGENT}@${DOMAIN}"
fi
CURRENT_NAME=$(git config --global user.name 2>/dev/null || echo "")
if [ -z "$CURRENT_NAME" ]; then
  git config --global user.name "${AGENT_UPPER}"
  echo "  Git name: ${AGENT_UPPER}"
fi

# ── Ownership ──
chown -R "${KINGDOM_USER}:" "$SSH_DIR" 2>/dev/null || true
chown -R "${KINGDOM_USER}:" "$HIVE_DIR" 2>/dev/null || true

echo "[04-keys] Done."
