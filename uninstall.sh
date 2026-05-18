#!/usr/bin/env bash
set -euo pipefail
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

systemctl --user disable --now afkwatch.timer 2>/dev/null || true
rm -f "$SYSTEMD_USER_DIR/afkwatch.service" "$SYSTEMD_USER_DIR/afkwatch.timer"
systemctl --user daemon-reload 2>/dev/null || true

rm -f "$BIN_DIR/afkwatch"
echo "uninstalled afkwatch CLI + timer."
echo "Snapshots in ~/.local/share/afkwatch were NOT removed. Delete manually if desired."
