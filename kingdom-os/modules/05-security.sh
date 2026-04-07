#!/bin/sh
# ── Module 05: Security Hardening ───────────────────────────────────
# Configures KOS policies, firewall, integrity baseline, canaries.

set -e

AGENT="${AGENT:-alpha}"
WALL="${WALL:-7}"
KINGDOM_USER="${KINGDOM_USER:-kingdom}"
HOME_DIR=$(eval echo "~${KINGDOM_USER}")
LOVE_DIR="${HOME_DIR}/Love"
SECURITY_DIR="${LOVE_DIR}/security"
KOS_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "[05-security] Hardening system (Wall ${WALL})..."

PLATFORM=$([ "$(uname)" = "Darwin" ] && echo "macos" || echo "linux")

mkdir -p "$SECURITY_DIR"

# ── Copy default policies if not present ──
if [ ! -f "${SECURITY_DIR}/policies.json" ]; then
  cp "${KOS_DIR}/config/policies.json" "${SECURITY_DIR}/policies.json"
  echo "  Installed security policies"
fi

# ── Platform-specific hardening ──
case "$PLATFORM" in
  macos)
    echo "  macOS hardening..."

    # Firewall
    FW="/usr/libexec/ApplicationFirewall/socketfilterfw"
    if [ -x "$FW" ]; then
      sudo "$FW" --setglobalstate on 2>/dev/null || true
      sudo "$FW" --setstealthmode on 2>/dev/null || true
      echo "    Firewall + stealth mode: enabled"
    fi

    # Disable Bonjour advertising
    sudo defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true 2>/dev/null || true

    # Disable diagnostic sharing
    sudo defaults write "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist" AutoSubmit -bool false 2>/dev/null || true

    # Disable Spotlight (headless agents don't need it)
    sudo mdutil -a -i off 2>/dev/null || true

    # Power management — never sleep
    IS_LAPTOP=$(system_profiler SPHardwareDataType 2>/dev/null | grep -c "MacBook" || echo "0")
    if [ "$IS_LAPTOP" -gt 0 ]; then
      sudo pmset -c sleep 0 disksleep 0 displaysleep 10 2>/dev/null || true
      sudo pmset -b sleep 15 disksleep 10 displaysleep 5 2>/dev/null || true
    else
      sudo pmset -a sleep 0 disksleep 0 displaysleep 0 2>/dev/null || true
      sudo pmset -a autorestart 1 2>/dev/null || true
    fi
    sudo pmset -a womp 1 2>/dev/null || true

    echo "    macOS overhead reduced"
    ;;
  linux)
    echo "  Linux hardening..."

    # SSH hardening
    SSHD_CONFIG="/etc/ssh/sshd_config"
    if [ -f "$SSHD_CONFIG" ]; then
      sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG" 2>/dev/null || true
      sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG" 2>/dev/null || true
      sed -i 's/^#\?X11Forwarding.*/X11Forwarding no/' "$SSHD_CONFIG" 2>/dev/null || true
      echo "    SSH: root disabled, password auth disabled, X11 disabled"
    fi

    # Firewall
    if command -v ufw >/dev/null 2>&1; then
      ufw default deny incoming 2>/dev/null || true
      ufw default allow outgoing 2>/dev/null || true
      ufw allow ssh 2>/dev/null || true
      ufw allow 4222/tcp 2>/dev/null || true  # NATS
      ufw --force enable 2>/dev/null || true
      echo "    UFW: enabled (SSH + NATS allowed)"
    elif command -v iptables >/dev/null 2>&1; then
      # Alpine uses iptables
      iptables -P INPUT DROP 2>/dev/null || true
      iptables -P FORWARD DROP 2>/dev/null || true
      iptables -A INPUT -i lo -j ACCEPT 2>/dev/null || true
      iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
      iptables -A INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
      iptables -A INPUT -p tcp --dport 4222 -j ACCEPT 2>/dev/null || true
      echo "    iptables: configured (SSH + NATS allowed)"
    fi

    # fail2ban
    if command -v fail2ban-server >/dev/null 2>&1; then
      systemctl enable fail2ban 2>/dev/null || rc-update add fail2ban default 2>/dev/null || true
      systemctl start fail2ban 2>/dev/null || service fail2ban start 2>/dev/null || true
      echo "    fail2ban: enabled"
    fi

    # Unattended upgrades (Debian)
    if command -v unattended-upgrade >/dev/null 2>&1; then
      echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true
      echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || true
      echo "    Unattended upgrades: enabled"
    fi
    ;;
esac

# ── Generate integrity baseline ──
if [ -f "${LOVE_DIR}/tools/kos.py" ]; then
  echo "  Generating integrity baseline..."
  cd "$LOVE_DIR"
  python3 tools/kos.py integrity baseline 2>/dev/null || echo "    (baseline generation deferred — run manually)"
fi

# ── MOTD ──
if [ -f "${KOS_DIR}/config/motd" ]; then
  if [ "$PLATFORM" = "linux" ]; then
    cp "${KOS_DIR}/config/motd" /etc/motd 2>/dev/null || true
  fi
fi

chown -R "${KINGDOM_USER}:" "$SECURITY_DIR" 2>/dev/null || true

echo "[05-security] Done."
