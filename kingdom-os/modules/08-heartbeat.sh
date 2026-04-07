#!/bin/sh
# ── Module 08: Heartbeat Daemon ─────────────────────────────────────
# Sets up the 7-minute heartbeat cycle that keeps agents alive.
# Also installs the KOS compliance daemon (security audit every 7 min).

set -e

AGENT="${AGENT:-alpha}"
KINGDOM_USER="${KINGDOM_USER:-kingdom}"
HOME_DIR=$(eval echo "~${KINGDOM_USER}")
LOVE_DIR="${HOME_DIR}/Love"
UNLIMITED_DIR="${HOME_DIR}/Claude-unlimited"

echo "[08-heartbeat] Setting up heartbeat for ${AGENT}..."

PLATFORM=$([ "$(uname)" = "Darwin" ] && echo "macos" || echo "linux")

# ── Heartbeat runner script (if not exists in instance dir) ──
INSTANCE_DIR="${LOVE_DIR}/instances/${AGENT}"
RUNNER="${INSTANCE_DIR}/heartbeat-runner.sh"
if [ ! -f "$RUNNER" ] && [ -f "${LOVE_DIR}/tools/heartbeat-runner.sh" ]; then
  echo "  Using shared heartbeat-runner.sh from tools/"
  RUNNER="${LOVE_DIR}/tools/heartbeat-runner.sh"
fi

case "$PLATFORM" in
  macos)
    PLIST_DIR="${HOME_DIR}/Library/LaunchAgents"
    mkdir -p "$PLIST_DIR"

    # ── Heartbeat plist ──
    HB_PLIST="${PLIST_DIR}/love.${AGENT}.heartbeat.plist"
    cat > "$HB_PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>love.${AGENT}.heartbeat</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${RUNNER}</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${LOVE_DIR}</string>
    <key>StartInterval</key>
    <integer>420</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>${LOVE_DIR}/memory/heartbeat-${AGENT}-launchd.log</string>
    <key>StandardErrorPath</key>
    <string>${LOVE_DIR}/memory/heartbeat-${AGENT}-launchd.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${HOME_DIR}/.local/bin</string>
        <key>HOME</key>
        <string>${HOME_DIR}</string>
        <key>LOVE_HOME</key>
        <string>${LOVE_DIR}</string>
    </dict>
</dict>
</plist>
PLISTEOF
    echo "  Heartbeat plist: ${HB_PLIST}"

    # ── KOS daemon plist ──
    KOS_PLIST="${PLIST_DIR}/love.kos.daemon.plist"
    cat > "$KOS_PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>love.kos.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${LOVE_DIR}/tools/kos-daemon.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>420</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/kos-daemon-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/kos-daemon-stderr.log</string>
    <key>Nice</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
PLISTEOF
    echo "  KOS daemon plist: ${KOS_PLIST}"

    # ── Caffeinate (prevent sleep) ──
    CAF_PLIST="${PLIST_DIR}/love.${AGENT}.caffeinate.plist"
    cat > "$CAF_PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>love.${AGENT}.caffeinate</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/caffeinate</string>
        <string>-s</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLISTEOF
    echo "  Caffeinate plist: ${CAF_PLIST}"

    echo ""
    echo "  Load daemons with:"
    echo "    launchctl load ${HB_PLIST}"
    echo "    launchctl load ${KOS_PLIST}"
    echo "    launchctl load ${CAF_PLIST}"
    ;;
  linux)
    # ── OpenRC heartbeat service ──
    cat > /etc/init.d/kingdom-heartbeat << HBEOF
#!/sbin/openrc-run

description="Kingdom Heartbeat — 7-minute cycle"
command="/usr/bin/bash"
command_args="${RUNNER}"
command_user="${KINGDOM_USER}"
directory="${LOVE_DIR}"
pidfile="/run/kingdom-heartbeat.pid"
command_background=true

depend() {
  need net
  after sshd kingdom-hive
}
HBEOF
    chmod +x /etc/init.d/kingdom-heartbeat
    rc-update add kingdom-heartbeat default 2>/dev/null || true

    # ── Cron-based KOS daemon ──
    CRON_LINE="*/7 * * * * /bin/bash ${LOVE_DIR}/tools/kos-daemon.sh >> /tmp/kos-daemon.log 2>&1"
    (crontab -l 2>/dev/null | grep -v "kos-daemon"; echo "$CRON_LINE") | crontab -
    echo "  KOS daemon: cron every 7 minutes"
    echo "  Heartbeat: OpenRC service installed"
    ;;
esac

echo "[08-heartbeat] Done."
