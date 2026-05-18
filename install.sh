#!/usr/bin/env bash
# afkwatch installer. Symlinks the CLI into ~/.local/bin and optionally
# installs a systemd user timer for hourly snapshots.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

mkdir -p "$BIN_DIR"
chmod +x "$HERE/afkwatch" "$HERE/modules/"*.sh

ln -sf "$HERE/afkwatch" "$BIN_DIR/afkwatch"
echo "linked $BIN_DIR/afkwatch -> $HERE/afkwatch"

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
    echo
    echo "NOTE: $BIN_DIR is not in your PATH."
    echo "      Add this to ~/.bashrc:    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

if [[ "${1:-}" == "--with-timer" ]]; then
    mkdir -p "$SYSTEMD_USER_DIR"
    cp "$HERE/systemd/afkwatch.service" "$SYSTEMD_USER_DIR/"
    cp "$HERE/systemd/afkwatch.timer"   "$SYSTEMD_USER_DIR/"
    # Patch the ExecStart path
    sed -i "s|__AFKWATCH_BIN__|$BIN_DIR/afkwatch|g" "$SYSTEMD_USER_DIR/afkwatch.service"
    systemctl --user daemon-reload
    systemctl --user enable --now afkwatch.timer
    echo "systemd user timer enabled: hourly snapshots."
fi

echo
echo "Installed. Try:"
echo "  afkwatch modules        # list modules"
echo "  afkwatch arm            # take an AFK baseline (run before stepping away)"
echo "  afkwatch check          # diff against baseline (run when you return)"
