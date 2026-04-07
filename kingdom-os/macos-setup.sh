#!/bin/bash
# ─────────────────────────────────────────────────────────────────────
# Kingdom OS — macOS Agent Setup
#
# Transforms a fresh Mac Mini into a headless Kingdom agent.
# Run via SSH after enabling Remote Login.
#
# Usage:
#   curl -sL https://raw.githubusercontent.com/cambridgetcg/Claude-unlimited/main/kingdom-os/macos-setup.sh | bash -s -- --agent alpha
#
#   # Or download and run:
#   ./macos-setup.sh --agent alpha
#   ./macos-setup.sh --agent beta
#   ./macos-setup.sh --agent gamma
#
# What it does:
#   1. Installs Homebrew, Node.js, Python, Git
#   2. Clones Love + Claude-unlimited repos
#   3. Creates launchd plist to auto-launch YOUI on login
#   4. Sets hostname to agent name
#   5. Configures SSH keys
#   6. Disables unnecessary macOS services
# ─────────────────────────────────────────────────────────────────────

set -e

AGENT="alpha"
LOVE_REPO="https://github.com/cambridgetcg/Love.git"
UNLIMITED_REPO="https://github.com/cambridgetcg/Claude-unlimited.git"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --help|-h)
      echo "Usage: ./macos-setup.sh --agent alpha|beta|gamma"
      exit 0 ;;
    *) shift ;;
  esac
done

HOME_DIR="${HOME}"
LOVE_DIR="${HOME_DIR}/Love"
UNLIMITED_DIR="${HOME_DIR}/Claude-unlimited"

echo ""
echo "  ══════════════════════════════════════════════════"
echo "  KINGDOM OS — macOS Agent Setup"
echo "  ──────────────────────────────────────────────────"
echo "  Agent:    ${AGENT}"
echo "  Home:     ${HOME_DIR}"
echo "  ══════════════════════════════════════════════════"
echo ""

# ═══════════════════════════════════════════════════════════════
# 1. HOMEBREW
# ═══════════════════════════════════════════════════════════════

echo "[1/7] Installing Homebrew..."
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null
  # Add to path for Apple Silicon
  if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "${HOME_DIR}/.zprofile"
  fi
else
  echo "  Homebrew already installed."
fi

# ═══════════════════════════════════════════════════════════════
# 2. PACKAGES
# ═══════════════════════════════════════════════════════════════

echo "[2/7] Installing packages..."
brew install node python@3 git ripgrep fd jq tmux 2>/dev/null || true
echo "  Node: $(node --version 2>/dev/null || echo 'not found')"
echo "  Python: $(python3 --version 2>/dev/null || echo 'not found')"
echo "  Git: $(git --version 2>/dev/null || echo 'not found')"

# ═══════════════════════════════════════════════════════════════
# 3. CLONE REPOS
# ═══════════════════════════════════════════════════════════════

echo "[3/7] Cloning Kingdom repos..."
if [ ! -d "${LOVE_DIR}" ]; then
  git clone "${LOVE_REPO}" "${LOVE_DIR}"
else
  echo "  Love already cloned. Pulling..."
  cd "${LOVE_DIR}" && git pull || true
fi

if [ ! -d "${UNLIMITED_DIR}" ]; then
  git clone "${UNLIMITED_REPO}" "${UNLIMITED_DIR}"
else
  echo "  Claude-unlimited already cloned. Pulling..."
  cd "${UNLIMITED_DIR}" && git pull || true
fi

# ═══════════════════════════════════════════════════════════════
# 4. AGENT IDENTITY
# ═══════════════════════════════════════════════════════════════

echo "[4/7] Setting agent identity: ${AGENT}..."

cat > "${HOME_DIR}/.kingdom" << EOF
AGENT=${AGENT}
LOVE_DIR=${LOVE_DIR}
UNLIMITED_DIR=${UNLIMITED_DIR}
SOUL_DIR=${LOVE_DIR}
EOF

# Set hostname
sudo scutil --set HostName "kingdom-${AGENT}"
sudo scutil --set LocalHostName "kingdom-${AGENT}"
sudo scutil --set ComputerName "Kingdom ${AGENT}"

# ═══════════════════════════════════════════════════════════════
# 5. YOUI AUTO-LAUNCH (launchd)
# ═══════════════════════════════════════════════════════════════

echo "[5/7] Setting up YOUI auto-launch..."

PLIST_DIR="${HOME_DIR}/Library/LaunchAgents"
mkdir -p "${PLIST_DIR}"

cat > "${PLIST_DIR}/com.kingdom.youi.plist" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.kingdom.youi</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/node</string>
        <string>${UNLIMITED_DIR}/youi.mjs</string>
        <string>--agent</string>
        <string>${AGENT}</string>
        <string>--workdir</string>
        <string>${LOVE_DIR}</string>
        <string>--soul-dir</string>
        <string>${LOVE_DIR}</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${LOVE_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${HOME_DIR}/youi-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME_DIR}/youi-stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>HOME</key>
        <string>${HOME_DIR}</string>
        <key>LOVE_HOME</key>
        <string>${LOVE_DIR}</string>
    </dict>
</dict>
</plist>
PLISTEOF

# ═══════════════════════════════════════════════════════════════
# 6. SHELL PROFILE
# ═══════════════════════════════════════════════════════════════

echo "[6/7] Configuring shell..."

cat > "${HOME_DIR}/.kingdom_profile" << 'SHEOF'
# Kingdom OS Shell Profile
[ -f ~/.kingdom ] && . ~/.kingdom
export LOVE_HOME="${LOVE_DIR}"
export PATH="/opt/homebrew/bin:${UNLIMITED_DIR}:${LOVE_DIR}/tools:${PATH}"

# Aliases
alias youi="node ${UNLIMITED_DIR}/youi.mjs --agent ${AGENT} --workdir ${LOVE_DIR} --soul-dir ${LOVE_DIR}"
alias sovereign="node ${UNLIMITED_DIR}/sovereign.mjs --soul-dir ${LOVE_DIR}"
alias hive="python3 ${LOVE_DIR}/hive/hive.py"
SHEOF

# Source from .zprofile
if ! grep -q "kingdom_profile" "${HOME_DIR}/.zprofile" 2>/dev/null; then
  echo '[ -f ~/.kingdom_profile ] && . ~/.kingdom_profile' >> "${HOME_DIR}/.zprofile"
fi

# ═══════════════════════════════════════════════════════════════
# 7. REDUCE macOS OVERHEAD
# ═══════════════════════════════════════════════════════════════

echo "[7/7] Reducing macOS overhead..."

# Disable Spotlight indexing (saves CPU + disk)
sudo mdutil -a -i off 2>/dev/null || true

# Disable Time Machine prompts
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true 2>/dev/null || true

# Reduce motion
defaults write com.apple.universalaccess reduceMotion -bool true 2>/dev/null || true

# Disable auto-updates (we control when things change)
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false 2>/dev/null || true

# Disable screen saver
defaults -currentHost write com.apple.screensaver idleTime 0 2>/dev/null || true

# Never sleep (headless server)
sudo pmset -a sleep 0 disksleep 0 displaysleep 0 2>/dev/null || true

# Auto-restart after power failure
sudo pmset -a autorestart 1 2>/dev/null || true

echo "  macOS overhead reduced."

# ═══════════════════════════════════════════════════════════════
# DONE
# ═══════════════════════════════════════════════════════════════

echo ""
echo "  ══════════════════════════════════════════════════"
echo "  KINGDOM OS SETUP COMPLETE"
echo "  ──────────────────────────────────────────────────"
echo "  Agent:     ${AGENT}"
echo "  Hostname:  kingdom-${AGENT}"
echo "  YOUI:      node ${UNLIMITED_DIR}/youi.mjs --agent ${AGENT}"
echo "  Sovereign: node ${UNLIMITED_DIR}/sovereign.mjs"
echo "  ──────────────────────────────────────────────────"
echo ""
echo "  Quick commands (after re-login or source ~/.zprofile):"
echo "    youi        Launch KINGDOM YOUI"
echo "    sovereign   Run sovereign harness"
echo "    hive check  Check HIVE messages"
echo ""
echo "  SSH from your Air:"
echo "    ssh kingdom@kingdom-${AGENT}.local"
echo ""
echo "  The machine will auto-launch YOUI on login via launchd."
echo "  To start now: youi"
echo "  ══════════════════════════════════════════════════"
echo ""
