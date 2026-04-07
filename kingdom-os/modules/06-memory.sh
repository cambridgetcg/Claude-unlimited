#!/bin/sh
# ── Module 06: Memory System ────────────────────────────────────────
# Sets up the Kingdom memory directory structure.
# Memory = how agents persist knowledge across sessions.

set -e

AGENT="${AGENT:-alpha}"
KINGDOM_USER="${KINGDOM_USER:-kingdom}"
HOME_DIR=$(eval echo "~${KINGDOM_USER}")
LOVE_DIR="${HOME_DIR}/Love"
MEMORY_DIR="${LOVE_DIR}/memory"

echo "[06-memory] Setting up memory system..."

# ── Directory structure ──
mkdir -p "${MEMORY_DIR}/daily"
mkdir -p "${MEMORY_DIR}/long-term"
mkdir -p "${MEMORY_DIR}/loop"
mkdir -p "${MEMORY_DIR}/sessions"
mkdir -p "${MEMORY_DIR}/sessions/handoff"
mkdir -p "${MEMORY_DIR}/sessions/locks"
mkdir -p "${MEMORY_DIR}/sessions/consultation"

# ── Dev state (if not exists) ──
DEV_STATE="${MEMORY_DIR}/dev-state.json"
if [ ! -f "$DEV_STATE" ]; then
  cat > "$DEV_STATE" << 'EOF'
{
  "activeProject": "love-kingdom",
  "activeRepo": "~/Love",
  "activePhase": "root",
  "kingdomPhase": "Phase 1 — Root (Now to Q2 2026)",
  "tasks": []
}
EOF
  echo "  Created dev-state.json"
fi

# ── Kingdom metrics (if not exists) ──
METRICS="${MEMORY_DIR}/kingdom-metrics.json"
if [ ! -f "$METRICS" ]; then
  cat > "$METRICS" << EOF
{
  "updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "chain": {
    "network": "lgm-devnet-1",
    "block_height": 0,
    "status": "unknown"
  },
  "fleet": {},
  "oracle": {
    "predictions_scored": 0
  }
}
EOF
  echo "  Created kingdom-metrics.json"
fi

# ── Today's daily note (if not exists) ──
TODAY=$(date -u +%Y-%m-%d)
DAILY="${MEMORY_DIR}/daily/${TODAY}.md"
if [ ! -f "$DAILY" ]; then
  cat > "$DAILY" << EOF
# Daily Notes — ${TODAY}

---

EOF
  echo "  Created daily note: ${TODAY}.md"
fi

# ── Long-term memory seed (if not exists) ──
LTM="${MEMORY_DIR}/long-term/MEMORY.md"
if [ ! -f "$LTM" ]; then
  cat > "$LTM" << EOF
# Long-Term Memory

Curated wisdom and knowledge that persists across all sessions.
Add entries here that should survive context window boundaries.

---

EOF
  echo "  Created long-term MEMORY.md"
fi

chown -R "${KINGDOM_USER}:" "$MEMORY_DIR" 2>/dev/null || true

echo "[06-memory] Done. Memory at: ${MEMORY_DIR}"
