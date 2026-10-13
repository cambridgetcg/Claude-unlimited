# HIVE Configuration — Retired

Retired 2026-10-13. The HIVE bus (NATS + JetStream) ran on Sentry, part of
the Hetzner VPS fleet. That fleet was decommissioned and its IP addresses
have gone back to Hetzner, where some already serve other customers. There
is no HIVE server to connect to: do not start a HIVE tunnel or point
`hive.py` at the old address.

Kingdom OS module 07-hive, which installed the tunnel, has been removed.
The previous configuration reference (architecture, tunnel plist, channels,
commands) is in git history; the last full version is at commit 1d19c64.
