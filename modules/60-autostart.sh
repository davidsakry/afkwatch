#!/usr/bin/env bash
# Autostart: desktop autostart entries + user systemd units (another classic persistence spot).
set -euo pipefail

case "${1:-}" in
    name)        echo "autostart" ;;
    description) echo "Desktop autostart entries and user systemd units" ;;
    snapshot)
        out="$2"
        # XDG autostart (system + user)
        for d in /etc/xdg/autostart "$HOME/.config/autostart"; do
            [[ -d "$d" ]] || continue
            ls -la "$d" 2>/dev/null >> "$out/autostart_listing.txt" || true
            # Hash each .desktop file so we catch edits too
            find "$d" -maxdepth 1 -type f -name '*.desktop' -exec sha256sum {} \; 2>/dev/null >> "$out/autostart_hashes.txt" || true
        done
        # User systemd units
        if [[ -d "$HOME/.config/systemd/user" ]]; then
            find "$HOME/.config/systemd/user" -maxdepth 2 -type f -exec sha256sum {} \; 2>/dev/null >> "$out/user_units.txt" || true
        fi
        # Drop the trailing summary line ("N unit files listed.") and the transient
        # session scopes (e.g. app-com.google.Chrome-15042.scope) which churn per launch.
        systemctl --user list-unit-files --no-pager 2>/dev/null \
            | grep -vE 'unit files listed|^app-.*\.scope|^$' | sort > "$out/user_unit_files.txt" || true
        systemctl list-unit-files --state=enabled --no-pager 2>/dev/null \
            | grep -vE 'unit files listed|^$' | sort > "$out/enabled_services.txt" || true
        ;;
    diff)
        old="$2" new="$3"
        for f in autostart_hashes.txt user_units.txt enabled_services.txt user_unit_files.txt; do
            [[ -f "$old/$f" && -f "$new/$f" ]] || continue
            d=$(diff "$old/$f" "$new/$f" 2>/dev/null || true)
            if [[ -n "$d" ]]; then
                echo "$f changed:"
                echo "$d" | grep -E '^[<>]' | head -20
            fi
        done
        ;;
esac
