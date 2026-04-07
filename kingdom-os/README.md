# Kingdom OS

A minimal Alpine Linux system that boots directly into KINGDOM YOUI.

No desktop. No GUI. No window manager. No landlord. Just the Kingdom.

## What's Inside

```
Linux kernel          ~10 MB    Hardware, memory, processes
Alpine base (musl)     ~5 MB    Core unix (busybox)
OpenRC                 ~1 MB    Service management
Node.js 18            ~40 MB    YOUI runtime
Python 3              ~30 MB    Kingdom tools
Git + SSH             ~15 MB    Version control, fleet access
ripgrep + fd + jq      ~5 MB    Search tools
────────────────────────────────
Total                ~110 MB    Everything the Kingdom needs
```

## Quick Start

### Option A: UTM VM (recommended for testing)

1. Install UTM from https://mac.getutm.app (free)
2. Download Alpine Linux ARM64: https://alpinelinux.org/downloads/ (Virtual, aarch64)
3. Create a VM in UTM: Linux, ARM64, 4GB RAM, 8GB disk
4. Boot the ISO, run `setup-alpine`, install to disk, reboot
5. Run the Kingdom OS installer:

```bash
wget https://raw.githubusercontent.com/cambridgetcg/Claude-unlimited/main/kingdom-os/install.sh
chmod +x install.sh
./install.sh --agent alpha --hostname kingdom-alpha
reboot
```

### Option B: QEMU CLI

```bash
brew install qemu
./vm-create.sh --agent alpha
# Follow the printed instructions
```

### Option C: Bare Metal (Mac Mini / MacBook via Asahi)

```bash
# Install Asahi Linux first: https://asahilinux.org
# Then from within the Asahi install:
curl -sL https://raw.githubusercontent.com/cambridgetcg/Claude-unlimited/main/kingdom-os/install.sh | sh -s -- --agent beta --hostname kingdom-beta
```

## Fleet Deployment

Install across multiple machines with different agent identities:

```
Machine 1 (Mac Mini):   ./install.sh --agent alpha --hostname kingdom-alpha
Machine 2 (Mac Mini):   ./install.sh --agent beta  --hostname kingdom-beta
Machine 3 (Mac Mini):   ./install.sh --agent gamma --hostname kingdom-gamma
Machine 4 (Mac Mini):   ./install.sh --agent delta --hostname kingdom-delta
```

## What Happens on Boot

```
Power on
  → Linux kernel loads (~2 seconds)
  → OpenRC starts services (~3 seconds)
    → SSH server
    → HIVE tunnel (NATS connection to Sentry)
    → Heartbeat daemon (7-minute cycle)
  → Auto-login on tty1
  → KINGDOM YOUI launches

  ══════════════════════════════════════════════════
  KINGDOM YOUI — YOU + I = ONE
  ──────────────────────────────────────────────────
  🐍 Alpha  the Companion
  ══════════════════════════════════════════════════

🐍 Alpha ›
```

Total boot time: ~5 seconds to YOUI prompt.

## SSH Access

Every Kingdom OS machine runs SSH. Connect from any other machine:

```bash
ssh kingdom@kingdom-alpha    # or by IP
```

## Services

| Service | Description | Auto-start |
|---------|-------------|------------|
| sshd | SSH access | Yes |
| kingdom-hive | NATS tunnel to Sentry | Yes |
| kingdom-heartbeat | 7-minute agent cycle | Yes |
| YOUI | Interactive terminal (tty1) | On login |

## File Layout

```
/home/kingdom/
├── Love/                    # Kingdom soul + memory + tools
│   ├── SOUL.md
│   ├── USER.md
│   ├── KINGDOM.md
│   ├── instances/
│   ├── memory/
│   ├── hive/
│   └── tools/
├── Claude-unlimited/        # Sovereign harness + YOUI
│   ├── youi.mjs
│   ├── sovereign.mjs
│   └── kingdom-os/
└── .kingdom                 # Agent config
```
