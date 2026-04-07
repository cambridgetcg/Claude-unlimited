#!/bin/sh
# ── Module 07: HIVE Communication ───────────────────────────────────
# Sets up the HIVE inter-instance messaging system.
# HIVE = NATS-based encrypted pub/sub between Kingdom citizens.

set -e

AGENT="${AGENT:-alpha}"
KINGDOM_USER="${KINGDOM_USER:-kingdom}"
HOME_DIR=$(eval echo "~${KINGDOM_USER}")
LOVE_DIR="${HOME_DIR}/Love"
SENTRY_IP="135.181.28.252"

echo "[07-hive] Setting up HIVE communication..."

PLATFORM=$([ "$(uname)" = "Darwin" ] && echo "macos" || echo "linux")

# ── Verify HIVE identity and key exist ──
HIVE_DIR="${HOME_DIR}/.love/hive"
if [ ! -f "${HIVE_DIR}/instance" ]; then
  echo "  ERROR: HIVE identity not set. Run module 03-identity first."
  exit 1
fi
if [ ! -f "${HIVE_DIR}/key" ]; then
  echo "  WARNING: HIVE encryption key not set. Run module 04-keys first."
fi

# ── HIVE tunnel service (SSH tunnel to Sentry NATS) ──
case "$PLATFORM" in
  macos)
    PLIST_DIR="${HOME_DIR}/Library/LaunchAgents"
    mkdir -p "$PLIST_DIR"
    PLIST="${PLIST_DIR}/love.${AGENT}.tunnel.plist"
    cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>love.${AGENT}.tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/ssh</string>
        <string>-N</string>
        <string>-L</string>
        <string>4222:localhost:4222</string>
        <string>-o</string>
        <string>StrictHostKeyChecking=accept-new</string>
        <string>-o</string>
        <string>ServerAliveInterval=30</string>
        <string>-o</string>
        <string>ServerAliveCountMax=3</string>
        <string>-o</string>
        <string>ExitOnForwardFailure=yes</string>
        <string>root@${SENTRY_IP}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/hive-tunnel-stderr.log</string>
    <key>ThrottleInterval</key>
    <integer>30</integer>
</dict>
</plist>
PLISTEOF
    echo "  HIVE tunnel plist: ${PLIST}"
    echo "  Load with: launchctl load ${PLIST}"
    ;;
  linux)
    # OpenRC service
    cat > /etc/init.d/kingdom-hive << HIVEEOF
#!/sbin/openrc-run

description="Kingdom HIVE SSH tunnel to NATS"
command="/usr/bin/ssh"
command_args="-N -L 4222:localhost:4222 root@${SENTRY_IP} -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes"
command_user="${KINGDOM_USER}"
pidfile="/run/kingdom-hive.pid"
command_background=true

depend() {
  need net
  after sshd
}
HIVEEOF
    chmod +x /etc/init.d/kingdom-hive
    rc-update add kingdom-hive default 2>/dev/null || \
    systemctl enable kingdom-hive 2>/dev/null || true
    echo "  HIVE tunnel service installed"
    ;;
esac

# ── Verify NATS connectivity ──
echo "  Testing HIVE connectivity..."
if command -v nc >/dev/null 2>&1; then
  if nc -z -w3 localhost 4222 2>/dev/null; then
    echo "  HIVE: CONNECTED (localhost:4222)"
  elif nc -z -w3 "$SENTRY_IP" 4222 2>/dev/null; then
    echo "  HIVE: Sentry reachable directly (tunnel not needed or not started)"
  else
    echo "  HIVE: NOT CONNECTED (start tunnel first)"
  fi
else
  echo "  HIVE: cannot test (nc not available)"
fi

echo "[07-hive] Done."
