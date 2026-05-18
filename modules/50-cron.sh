#!/usr/bin/env bash
# Cron + systemd timers: detect new scheduled tasks (a classic persistence vector).
set -euo pipefail

case "${1:-}" in
    name)        echo "cron" ;;
    description) echo "Cron jobs and systemd timers" ;;
    snapshot)
        out="$2"
        crontab -l 2>/dev/null > "$out/user_crontab.txt" || echo "(no crontab)" > "$out/user_crontab.txt"
        # System cron locations (readable bits only)
        for d in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
            [[ -d "$d" && -r "$d" ]] && ls -la "$d" 2>/dev/null >> "$out/system_cron.txt" || true
        done
        # /etc/crontab itself
        [[ -r /etc/crontab ]] && cat /etc/crontab > "$out/etc_crontab.txt" || true
        # Systemd timers (user + system). We only keep the UNIT and ACTIVATES columns —
        # the "NEXT" / "LEFT" / "LAST" / "PASSED" fields are relative time and would
        # flap on every snapshot.
        systemctl list-timers --all --no-pager 2>/dev/null \
            | awk 'NR>1 && NF>=6 {print $(NF-1), $NF}' | sort -u > "$out/timers_system.txt" || true
        systemctl --user list-timers --all --no-pager 2>/dev/null \
            | awk 'NR>1 && NF>=6 {print $(NF-1), $NF}' | sort -u > "$out/timers_user.txt" || true
        ;;
    diff)
        old="$2" new="$3"
        for f in user_crontab.txt etc_crontab.txt system_cron.txt timers_system.txt timers_user.txt; do
            [[ -f "$old/$f" && -f "$new/$f" ]] || continue
            d=$(diff -u "$old/$f" "$new/$f" 2>/dev/null || true)
            if [[ -n "$d" ]]; then
                echo "$f changed:"
                echo "$d" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | head -20
            fi
        done
        ;;
esac
