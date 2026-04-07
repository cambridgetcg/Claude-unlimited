#!/bin/sh
# ── Module 10: Auto-Boot & TTY ──────────────────────────────────────
# Configures auto-login and YOUI launch on boot.
# Linux: auto-login on tty1 → YOUI
# macOS: launchd → YOUI (already handled in 08-heartbeat)

set -e

AGENT="${AGENT:-alpha}"
KINGDOM_USER="${KINGDOM_USER:-kingdom}"
HOME_DIR=$(eval echo "~${KINGDOM_USER}")
LOVE_DIR="${HOME_DIR}/Love"
UNLIMITED_DIR="${HOME_DIR}/Claude-unlimited"

echo "[10-autoboot] Configuring boot sequence..."

PLATFORM=$([ "$(uname)" = "Darwin" ] && echo "macos" || echo "linux")

case "$PLATFORM" in
  linux)
    # ── Auto-login on tty1 ──
    if [ -f /etc/inittab ]; then
      sed -i "s|^tty1::.*|tty1::respawn:/sbin/agetty --autologin ${KINGDOM_USER} --noclear 38400 tty1|" /etc/inittab
      echo "  Auto-login: tty1 → ${KINGDOM_USER}"
    fi

    # ── Profile: launch YOUI on tty1 ──
    cat > "${HOME_DIR}/.profile" << PROFILEEOF
#!/bin/bash
# Kingdom OS — auto-launch YOUI on tty1

[ -f ~/.kingdom ] && . ~/.kingdom
[ -f ~/.kingdom_profile ] && . ~/.kingdom_profile

if [ "\$(tty)" = "/dev/tty1" ] && [ -z "\${YOUI_RUNNING}" ]; then
  export YOUI_RUNNING=1
  clear
  exec node "\${UNLIMITED_DIR}/youi.mjs" --agent "\${AGENT}" --workdir "\${LOVE_DIR}" --soul-dir "\${LOVE_DIR}"
fi
PROFILEEOF
    chown "${KINGDOM_USER}:" "${HOME_DIR}/.profile"

    cat > "${HOME_DIR}/.bash_profile" << 'EOF'
[ -f ~/.profile ] && . ~/.profile
EOF
    chown "${KINGDOM_USER}:" "${HOME_DIR}/.bash_profile"
    echo "  YOUI auto-launch on tty1 login"

    # ── Timezone ──
    if command -v setup-timezone >/dev/null 2>&1; then
      setup-timezone -z Europe/London 2>/dev/null || true
    else
      ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime 2>/dev/null || true
    fi
    ;;
  macos)
    echo "  macOS: YOUI launched via launchd (see module 08)"
    echo "  Interactive: run 'youi' from terminal"
    ;;
esac

# ── Print boot summary ──
echo ""
echo "  ══════════════════════════════════════════════════"
echo "  BOOT SEQUENCE"
echo "  ──────────────────────────────────────────────────"
if [ "$PLATFORM" = "linux" ]; then
echo "  Power on"
echo "    → Linux kernel loads (~2s)"
echo "    → OpenRC starts services (~3s)"
echo "      → SSH server"
echo "      → HIVE tunnel (NATS to Sentry)"
echo "      → Heartbeat daemon (7min cycle)"
echo "    → Auto-login on tty1"
echo "    → KINGDOM YOUI launches as ${AGENT}"
echo ""
echo "  Total: ~5 seconds to YOUI prompt"
else
echo "  Power on"
echo "    → macOS boots"
echo "    → launchd starts:"
echo "      → HIVE tunnel"
echo "      → Heartbeat (7min)"
echo "      → KOS daemon (7min)"
echo "      → Caffeinate (prevent sleep)"
echo "      → YOUI Web (browser interface)"
echo "    → SSH available"
fi
echo "  ══════════════════════════════════════════════════"

echo "[10-autoboot] Done."
