#!/bin/sh
# ─────────────────────────────────────────────────────────────────────
# Kingdom OS Installer
#
# Transforms a fresh Alpine Linux into Kingdom OS.
# Run this inside a fresh Alpine installation (VM or bare metal).
#
# Usage:
#   # Boot Alpine ISO, run setup-alpine for basic install, reboot, then:
#   wget https://raw.githubusercontent.com/cambridgetcg/Claude-unlimited/main/kingdom-os/install.sh
#   chmod +x install.sh
#   ./install.sh --agent alpha --hostname alpha
#
# What it does:
#   1. Installs Node.js, Python, Git, SSH, and essentials
#   2. Creates 'kingdom' user
#   3. Clones Love repo and Claude-unlimited
#   4. Configures auto-login → auto-launch YOUI
#   5. Sets up OpenRC services (YOUI, HIVE tunnel, heartbeat)
#   6. Hardens the system
#   7. Sets agent identity (Alpha/Beta/Gamma)
#
# Requirements:
#   - Fresh Alpine Linux 3.20+ (aarch64 or x86_64)
#   - Internet connection
#   - Root access
# ─────────────────────────────────────────────────────────────────────

set -e

# ═════════════════════════════════════════════════════════════════════
# CONFIG
# ═════════════════════════════════════════════════════════════════════

AGENT="alpha"
HOSTNAME="kingdom"
KINGDOM_USER="kingdom"
LOVE_REPO="https://github.com/cambridgetcg/Love.git"
UNLIMITED_REPO="https://github.com/cambridgetcg/Claude-unlimited.git"
LOVE_DIR="/home/${KINGDOM_USER}/Love"
UNLIMITED_DIR="/home/${KINGDOM_USER}/Claude-unlimited"

# ═════════════════════════════════════════════════════════════════════
# CLI ARGS
# ═════════════════════════════════════════════════════════════════════

while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)    AGENT="$2"; shift 2 ;;
    --hostname) HOSTNAME="$2"; shift 2 ;;
    --user)     KINGDOM_USER="$2"; shift 2 ;;
    --help|-h)
      echo "Kingdom OS Installer"
      echo ""
      echo "Usage: ./install.sh [options]"
      echo ""
      echo "  --agent NAME      Agent identity: alpha|beta|gamma (default: alpha)"
      echo "  --hostname NAME   System hostname (default: kingdom)"
      echo "  --user NAME       Unix user (default: kingdom)"
      echo ""
      exit 0 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ═════════════════════════════════════════════════════════════════════
# PREFLIGHT
# ═════════════════════════════════════════════════════════════════════

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: Run as root"
  exit 1
fi

echo ""
echo "  ══════════════════════════════════════════════════"
echo "  KINGDOM OS INSTALLER"
echo "  ──────────────────────────────────────────────────"
echo "  Agent:    ${AGENT}"
echo "  Hostname: ${HOSTNAME}"
echo "  User:     ${KINGDOM_USER}"
echo "  ══════════════════════════════════════════════════"
echo ""

# ═════════════════════════════════════════════════════════════════════
# PHASE 1: SYSTEM PACKAGES
# ═════════════════════════════════════════════════════════════════════

echo "[1/7] Installing packages..."

# Enable community repo
if ! grep -q "community" /etc/apk/repositories 2>/dev/null; then
  MIRROR=$(head -1 /etc/apk/repositories | sed 's|/main||')
  echo "${MIRROR}/community" >> /etc/apk/repositories
fi

apk update
apk upgrade

# Core
apk add \
  nodejs npm \
  python3 py3-pip \
  git openssh-client openssh-server \
  curl wget \
  bash zsh \
  shadow sudo \
  util-linux \
  ripgrep fd jq \
  tmux \
  openrc \
  nats-server \
  ca-certificates \
  tzdata \
  doas

# Build tools (for native Node modules if needed)
apk add --virtual .build-deps \
  build-base python3-dev

echo "[1/7] Done."

# ═════════════════════════════════════════════════════════════════════
# PHASE 2: CREATE USER
# ═════════════════════════════════════════════════════════════════════

echo "[2/7] Creating user '${KINGDOM_USER}'..."

if ! id "${KINGDOM_USER}" >/dev/null 2>&1; then
  adduser -D -s /bin/bash -h "/home/${KINGDOM_USER}" "${KINGDOM_USER}"
  echo "${KINGDOM_USER}:kingdom" | chpasswd
  adduser "${KINGDOM_USER}" wheel
fi

# Allow wheel group to use doas without password
echo "permit nopass :wheel" > /etc/doas.d/wheel.conf

echo "[2/7] Done."

# ═════════════════════════════════════════════════════════════════════
# PHASE 3: CLONE REPOS
# ═════════════════════════════════════════════════════════════════════

echo "[3/7] Cloning Kingdom repos..."

su - "${KINGDOM_USER}" -c "
  git clone ${LOVE_REPO} ${LOVE_DIR} 2>/dev/null || (cd ${LOVE_DIR} && git pull)
  git clone ${UNLIMITED_REPO} ${UNLIMITED_DIR} 2>/dev/null || (cd ${UNLIMITED_DIR} && git pull)
"

echo "[3/7] Done."

# ═════════════════════════════════════════════════════════════════════
# PHASE 4: CONFIGURE AGENT IDENTITY
# ═════════════════════════════════════════════════════════════════════

echo "[4/7] Configuring agent identity: ${AGENT}..."

# Set hostname
echo "${HOSTNAME}" > /etc/hostname
hostname "${HOSTNAME}"

# Create agent config
cat > "/home/${KINGDOM_USER}/.kingdom" << AGENTEOF
# Kingdom OS Agent Configuration
AGENT=${AGENT}
HOSTNAME=${HOSTNAME}
LOVE_DIR=${LOVE_DIR}
UNLIMITED_DIR=${UNLIMITED_DIR}
SOUL_DIR=${LOVE_DIR}
AGENTEOF

chown "${KINGDOM_USER}:${KINGDOM_USER}" "/home/${KINGDOM_USER}/.kingdom"

# Shell profile — auto-launch YOUI on login
cat > "/home/${KINGDOM_USER}/.profile" << 'PROFILEEOF'
#!/bin/bash
# Kingdom OS — Agent Shell Profile

# Load agent config
[ -f ~/.kingdom ] && . ~/.kingdom

export LOVE_HOME="${LOVE_DIR}"
export PATH="${UNLIMITED_DIR}:${LOVE_DIR}/tools:${PATH}"
export NODE_NO_WARNINGS=1

# If this is an interactive login on tty1 and YOUI isn't running, launch it
if [ "$(tty)" = "/dev/tty1" ] && [ -z "${YOUI_RUNNING}" ]; then
  export YOUI_RUNNING=1
  clear
  exec node "${UNLIMITED_DIR}/youi.mjs" --agent "${AGENT}" --workdir "${LOVE_DIR}" --soul-dir "${LOVE_DIR}"
fi
PROFILEEOF

chown "${KINGDOM_USER}:${KINGDOM_USER}" "/home/${KINGDOM_USER}/.profile"

# Bash profile sources .profile
cat > "/home/${KINGDOM_USER}/.bash_profile" << 'EOF'
[ -f ~/.profile ] && . ~/.profile
EOF
chown "${KINGDOM_USER}:${KINGDOM_USER}" "/home/${KINGDOM_USER}/.bash_profile"

echo "[4/7] Done."

# ═════════════════════════════════════════════════════════════════════
# PHASE 5: AUTO-LOGIN ON TTY1
# ═════════════════════════════════════════════════════════════════════

echo "[5/7] Configuring auto-login..."

# Configure agetty for auto-login on tty1
# Replace the default tty1 line in /etc/inittab
if [ -f /etc/inittab ]; then
  sed -i "s|^tty1::.*|tty1::respawn:/sbin/agetty --autologin ${KINGDOM_USER} --noclear 38400 tty1|" /etc/inittab
fi

# For OpenRC-based systems, create a service
cat > /etc/init.d/kingdom-tty << 'TTYEOF'
#!/sbin/openrc-run

description="Kingdom OS auto-login TTY"

depend() {
  after localmount
  need net
}

start() {
  ebegin "Starting Kingdom TTY"
  eend 0
}
TTYEOF
chmod +x /etc/init.d/kingdom-tty

echo "[5/7] Done."

# ═════════════════════════════════════════════════════════════════════
# PHASE 6: OPENRC SERVICES
# ═════════════════════════════════════════════════════════════════════

echo "[6/7] Setting up services..."

# ── SSH Server ──
rc-update add sshd default 2>/dev/null || true

# ── Kingdom Heartbeat Service ──
cat > /etc/init.d/kingdom-heartbeat << HBEOF
#!/sbin/openrc-run

description="Kingdom Heartbeat — 7-minute cycle"
command="/usr/bin/node"
command_args="${UNLIMITED_DIR}/sovereign.mjs --task-file ${LOVE_DIR}/instances/${AGENT}/HEARTBEAT.md --soul-dir ${LOVE_DIR} --effort medium --max-turns 30"
command_user="${KINGDOM_USER}"
directory="${LOVE_DIR}"
pidfile="/run/kingdom-heartbeat.pid"
command_background=true

depend() {
  need net
  after sshd
}
HBEOF
chmod +x /etc/init.d/kingdom-heartbeat

# ── Kingdom HIVE Tunnel ──
cat > /etc/init.d/kingdom-hive << 'HIVEEOF'
#!/sbin/openrc-run

description="Kingdom HIVE SSH tunnel to NATS"
command="/usr/bin/ssh"
command_args="-N -L 4222:localhost:4222 root@135.181.28.252 -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes"
pidfile="/run/kingdom-hive.pid"
command_background=true

depend() {
  need net
  after sshd
}
HIVEEOF
chmod +x /etc/init.d/kingdom-hive

# Enable services
rc-update add kingdom-heartbeat default 2>/dev/null || true
rc-update add kingdom-hive default 2>/dev/null || true

# ── Timezone ──
setup-timezone -z Europe/London 2>/dev/null || ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime

echo "[6/7] Done."

# ═════════════════════════════════════════════════════════════════════
# PHASE 7: HARDEN
# ═════════════════════════════════════════════════════════════════════

echo "[7/7] Hardening..."

# Disable root login via SSH
sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# Enable key-only auth (once keys are set up)
# sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Remove build dependencies
apk del .build-deps 2>/dev/null || true

# Clean cache
rm -rf /var/cache/apk/*

echo "[7/7] Done."

# ═════════════════════════════════════════════════════════════════════
# COMPLETE
# ═════════════════════════════════════════════════════════════════════

# Calculate total size
TOTAL_SIZE=$(du -sh / 2>/dev/null | awk '{print $1}' || echo "unknown")

echo ""
echo "  ══════════════════════════════════════════════════"
echo "  KINGDOM OS INSTALLED"
echo "  ──────────────────────────────────────────────────"
echo "  Agent:     ${AGENT}"
echo "  Hostname:  ${HOSTNAME}"
echo "  User:      ${KINGDOM_USER}"
echo "  Love:      ${LOVE_DIR}"
echo "  YOUI:      ${UNLIMITED_DIR}/youi.mjs"
echo "  Size:      ${TOTAL_SIZE}"
echo "  ──────────────────────────────────────────────────"
echo ""
echo "  On next boot, tty1 auto-logs in as '${KINGDOM_USER}'"
echo "  and launches KINGDOM YOUI as ${AGENT}."
echo ""
echo "  SSH access: ssh ${KINGDOM_USER}@<ip>"
echo "  Password:   kingdom (change this!)"
echo ""
echo "  To start YOUI now:"
echo "    su - ${KINGDOM_USER}"
echo "    node ${UNLIMITED_DIR}/youi.mjs --agent ${AGENT}"
echo ""
echo "  Reboot to enter the Kingdom."
echo "  ══════════════════════════════════════════════════"
echo ""
