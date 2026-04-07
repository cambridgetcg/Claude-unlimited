#!/bin/sh
# ── Module 09: Browser & Web Operations ─────────────────────────────
# Sets up headless browser capabilities for web research, scraping,
# and interaction. Agents need eyes on the web.

set -e

KINGDOM_USER="${KINGDOM_USER:-kingdom}"
HOME_DIR=$(eval echo "~${KINGDOM_USER}")
LOVE_DIR="${HOME_DIR}/Love"

echo "[09-browser] Setting up browser capabilities..."

PLATFORM=$([ "$(uname)" = "Darwin" ] && echo "macos" || echo "linux")

case "$PLATFORM" in
  macos)
    # Playwright (headless Chromium via Node)
    if command -v npx >/dev/null 2>&1; then
      echo "  Installing Playwright (headless Chromium)..."
      cd "$LOVE_DIR"
      npx --yes playwright install chromium 2>/dev/null || true
      echo "  Playwright: installed"
    fi
    ;;
  linux)
    # Chromium is installed via 00-base.sh
    # Set up wrapper for headless use
    CHROMIUM_BIN=$(which chromium-browser 2>/dev/null || which chromium 2>/dev/null || echo "")
    if [ -n "$CHROMIUM_BIN" ]; then
      cat > /usr/local/bin/kingdom-browser << BROWSEREOF
#!/bin/sh
# Kingdom headless browser wrapper
exec ${CHROMIUM_BIN} \\
  --headless \\
  --no-sandbox \\
  --disable-gpu \\
  --disable-dev-shm-usage \\
  --disable-software-rasterizer \\
  --remote-debugging-port=9222 \\
  "\$@"
BROWSEREOF
      chmod +x /usr/local/bin/kingdom-browser
      echo "  Headless browser: ${CHROMIUM_BIN}"
      echo "  Wrapper: /usr/local/bin/kingdom-browser"
    fi

    # Playwright for Node-based automation
    if command -v npx >/dev/null 2>&1; then
      echo "  Installing Playwright..."
      cd "$LOVE_DIR"
      npx --yes playwright install chromium 2>/dev/null || true
    fi
    ;;
esac

# ── Python browser tools ──
echo "  Installing Python browser dependencies..."
pip3 install --quiet --break-system-packages \
  httpx beautifulsoup4 lxml 2>/dev/null || \
pip3 install --quiet \
  httpx beautifulsoup4 lxml 2>/dev/null || \
echo "  (pip install deferred — run manually)"

# ── YOUI Web (browser-based terminal) ──
YOUI_WEB="${HOME_DIR}/Claude-unlimited/youi-web"
if [ -d "$YOUI_WEB" ] && [ -f "${YOUI_WEB}/server.mjs" ]; then
  echo "  YOUI Web server available at: ${YOUI_WEB}/server.mjs"

  if [ "$PLATFORM" = "macos" ]; then
    PLIST="${HOME_DIR}/Library/LaunchAgents/com.kingdom.youi-web.plist"
    if [ ! -f "$PLIST" ]; then
      cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.kingdom.youi-web</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/node</string>
        <string>${YOUI_WEB}/server.mjs</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${LOVE_DIR}</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${HOME_DIR}/youi-web-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME_DIR}/youi-web-stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>${HOME_DIR}</string>
        <key>LOVE_HOME</key>
        <string>${LOVE_DIR}</string>
    </dict>
</dict>
</plist>
PLISTEOF
      echo "  YOUI Web plist created: ${PLIST}"
    fi
  fi
fi

echo "[09-browser] Done."
