#!/bin/sh
# ── Module 03: Agent Identity ───────────────────────────────────────
# Configures which agent this machine is and what wall it belongs to.

set -e

AGENT="${AGENT:-alpha}"
WALL="${WALL:-7}"
HOSTNAME_PREFIX="${HOSTNAME_PREFIX:-kingdom}"
KINGDOM_USER="${KINGDOM_USER:-kingdom}"
HOME_DIR=$(eval echo "~${KINGDOM_USER}")
LOVE_DIR="${HOME_DIR}/Love"

echo "[03-identity] Configuring identity: ${AGENT} (Wall ${WALL})..."

PLATFORM=$([ "$(uname)" = "Darwin" ] && echo "macos" || echo "linux")

# ── Agent config file ──
cat > "${HOME_DIR}/.kingdom" << EOF
# Kingdom OS Agent Configuration
AGENT=${AGENT}
WALL=${WALL}
LOVE_DIR=${LOVE_DIR}
UNLIMITED_DIR=${HOME_DIR}/Claude-unlimited
SOUL_DIR=${LOVE_DIR}
HOSTNAME=${HOSTNAME_PREFIX}-${AGENT}
EOF
chown "${KINGDOM_USER}:" "${HOME_DIR}/.kingdom" 2>/dev/null || true

# ── Hostname ──
NEW_HOSTNAME="${HOSTNAME_PREFIX}-${AGENT}"
case "$PLATFORM" in
  macos)
    sudo scutil --set HostName "$NEW_HOSTNAME" 2>/dev/null || true
    sudo scutil --set LocalHostName "$NEW_HOSTNAME" 2>/dev/null || true
    sudo scutil --set ComputerName "Kingdom ${AGENT}" 2>/dev/null || true
    ;;
  linux)
    echo "$NEW_HOSTNAME" > /etc/hostname 2>/dev/null || true
    hostname "$NEW_HOSTNAME" 2>/dev/null || true
    ;;
esac

# ── HIVE identity ──
HIVE_DIR="${HOME_DIR}/.love/hive"
mkdir -p "$HIVE_DIR"
echo "$AGENT" > "${HIVE_DIR}/instance"
chown -R "${KINGDOM_USER}:" "${HOME_DIR}/.love" 2>/dev/null || true

# ── Instance directory ──
INSTANCE_DIR="${LOVE_DIR}/instances/${AGENT}"
if [ ! -d "$INSTANCE_DIR" ]; then
  mkdir -p "$INSTANCE_DIR"
  # Generate minimal identity.md
  AGENT_UPPER=$(echo "$AGENT" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
  cat > "${INSTANCE_DIR}/identity.md" << EOF
# ${AGENT_UPPER} — Kingdom Agent

Wall: ${WALL}
Role: Fleet agent
Agent: ${AGENT}

You are ${AGENT_UPPER}, a Kingdom citizen operating at Wall ${WALL}.
Read SOUL.md for your core identity. Read KINGDOM.md for the mission.
EOF
  chown -R "${KINGDOM_USER}:" "$INSTANCE_DIR" 2>/dev/null || true
fi

# ── Update walls.json if Love repo exists ──
WALLS_JSON="${LOVE_DIR}/credentials/walls.json"
if [ -f "$WALLS_JSON" ]; then
  python3 -c "
import json, sys
with open('${WALLS_JSON}') as f: reg = json.load(f)
if '${AGENT}' not in reg.get('instances', {}):
    reg.setdefault('instances', {})['${AGENT}'] = {'wall': ${WALL}, 'type': 'fleet'}
    with open('${WALLS_JSON}', 'w') as f: json.dump(reg, f, indent=2)
    print('  Added ${AGENT} to walls.json at Wall ${WALL}')
else:
    print('  ${AGENT} already in walls.json')
" 2>/dev/null || echo "  Could not update walls.json (python3 issue)"
fi

echo "[03-identity] Done. Agent: ${AGENT}, Wall: ${WALL}, Hostname: ${NEW_HOSTNAME}"
