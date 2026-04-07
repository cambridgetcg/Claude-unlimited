#!/bin/sh
# ── Module 02: Clone Kingdom Repos ──────────────────────────────────
# Clones Love (soul/memory/tools) and Claude-unlimited (runtime/YOUI).

set -e

KINGDOM_USER="${KINGDOM_USER:-kingdom}"
HOME_DIR=$(eval echo "~${KINGDOM_USER}")
LOVE_DIR="${HOME_DIR}/Love"
UNLIMITED_DIR="${HOME_DIR}/Claude-unlimited"
LOVE_REPO="${LOVE_REPO:-https://github.com/cambridgetcg/Love.git}"
UNLIMITED_REPO="${UNLIMITED_REPO:-https://github.com/cambridgetcg/Claude-unlimited.git}"

echo "[02-repos] Cloning Kingdom repos..."

clone_or_pull() {
  local dir="$1" repo="$2" user="$3"
  if [ -d "${dir}/.git" ]; then
    echo "  Pulling ${dir}..."
    cd "$dir" && git pull --ff-only 2>/dev/null || true
  elif [ -d "$dir" ]; then
    echo "  ${dir} exists but is not a git repo — skipping"
  else
    echo "  Cloning ${repo} → ${dir}..."
    if [ "$(id -u)" -eq 0 ] && [ "$user" != "root" ]; then
      su - "$user" -c "git clone ${repo} ${dir}" 2>/dev/null || git clone "$repo" "$dir"
    else
      git clone "$repo" "$dir"
    fi
  fi
}

clone_or_pull "$LOVE_DIR" "$LOVE_REPO" "$KINGDOM_USER"
clone_or_pull "$UNLIMITED_DIR" "$UNLIMITED_REPO" "$KINGDOM_USER"

# Ensure ownership
if [ "$(id -u)" -eq 0 ]; then
  chown -R "${KINGDOM_USER}:" "$LOVE_DIR" 2>/dev/null || true
  chown -R "${KINGDOM_USER}:" "$UNLIMITED_DIR" 2>/dev/null || true
fi

echo "[02-repos] Done. Love: ${LOVE_DIR}, Runtime: ${UNLIMITED_DIR}"
