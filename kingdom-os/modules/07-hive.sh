#!/bin/sh
# ── Module 07: HIVE Communication ───────────────────────────────────
set -e
. "$(dirname "$0")/_common.sh"

echo "[07-hive] Setting up HIVE (${PLATFORM})..."

[ ! -f "${HIVE_DIR}/instance" ] && { echo "  ERROR: Run module 03 first"; exit 1; }

case "$PLATFORM" in
  macos)
    ensure_dir "$PLIST_DIR"
    cat > "${PLIST_DIR}/love.${AGENT}.tunnel.plist" << PLISTEOF
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
    echo "  Tunnel plist: ${PLIST_DIR}/love.${AGENT}.tunnel.plist"
    ;;
  alpine|debian)
    cat > /etc/init.d/kingdom-hive << SVCEOF
#!/sbin/openrc-run
description="Kingdom HIVE SSH tunnel to NATS"
command="/usr/bin/ssh"
command_args="-N -L 4222:localhost:4222 root@${SENTRY_IP} -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes"
command_user="${KINGDOM_USER}"
pidfile="/run/kingdom-hive.pid"
command_background=true
depend() { need net; after sshd; }
SVCEOF
    chmod +x /etc/init.d/kingdom-hive
    rc-update add kingdom-hive default 2>/dev/null || true
    echo "  HIVE tunnel service installed"
    ;;
esac

# Connectivity test
if command -v nc >/dev/null 2>&1; then
  if nc -z -w3 localhost 4222 2>/dev/null; then
    echo "  HIVE: CONNECTED"
  else
    echo "  HIVE: not connected (start tunnel first)"
  fi
fi

echo "[07-hive] Done."
