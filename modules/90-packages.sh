#!/usr/bin/env bash
# Packages module: detect newly installed or removed packages.
set -euo pipefail

case "${1:-}" in
    name)        echo "packages" ;;
    description) echo "Installed packages (apt, snap, flatpak)" ;;
    snapshot)
        out="$2"
        if command -v dpkg-query >/dev/null 2>&1; then
            dpkg-query -W -f='${Package} ${Version}\n' 2>/dev/null | sort > "$out/apt.txt" || true
        fi
        if command -v snap >/dev/null 2>&1; then
            snap list 2>/dev/null | tail -n +2 | awk '{print $1, $2}' | sort > "$out/snap.txt" || true
        fi
        if command -v flatpak >/dev/null 2>&1; then
            flatpak list --app --columns=application,version 2>/dev/null | sort > "$out/flatpak.txt" || true
        fi
        ;;
    diff)
        old="$2" new="$3"
        for f in apt.txt snap.txt flatpak.txt; do
            [[ -f "$old/$f" && -f "$new/$f" ]] || continue
            added=$(comm -13 "$old/$f" "$new/$f" || true)
            removed=$(comm -23 "$old/$f" "$new/$f" || true)
            if [[ -n "$added" || -n "$removed" ]]; then
                echo "${f%.txt}:"
                [[ -n "$added"   ]] && echo "$added"   | sed 's/^/  + /'
                [[ -n "$removed" ]] && echo "$removed" | sed 's/^/  - /'
            fi
        done
        ;;
esac
