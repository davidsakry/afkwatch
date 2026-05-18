#!/usr/bin/env bash
# Processes module: snapshot the running process tree, diff for new/disappeared processes.
set -euo pipefail

case "${1:-}" in
    name)        echo "processes" ;;
    description) echo "Running processes (new processes, unexpected daemons)" ;;
    snapshot)
        out="$2"
        # Stable per-process identity: user + command (no PID, no times, no CPU).
        # Filter kernel threads — they cycle constantly and would dominate every diff.
        # Kernel threads have parent PID 2 (kthreadd). Capture them separately.
        ps -eo user,ppid,comm --no-headers 2>/dev/null \
            | awk '$2 != 2 && $3 != "kthreadd" {print $1, $3}' \
            | sort -u > "$out/procs.txt" || true
        # Full command lines (filtered) for the report
        ps -eo user,pid,ppid,stat,start_time,command --no-headers 2>/dev/null \
            | awk '$3 != 2 && $6 !~ /^\[/' \
            | sort -k1,1 -k6 > "$out/procs_full.txt" || true
        # Listening daemons separately (often the interesting bit)
        ps -eo user,comm,command --no-headers 2>/dev/null \
            | awk '$2 ~ /sshd|nc|ncat|socat|cron|atd|telnet|rdesktop|x11vnc|vncserver|screen|tmux|python.*http|python.*-m/' \
            | sort -u > "$out/notable.txt" || true
        ;;
    diff)
        old="$2" new="$3"
        if [[ -f "$old/procs.txt" && -f "$new/procs.txt" ]]; then
            added=$(comm -13 "$old/procs.txt" "$new/procs.txt" || true)
            if [[ -n "$added" ]]; then
                echo "new (user, command):"
                echo "$added" | head -30
            fi
        fi
        if [[ -f "$old/notable.txt" && -f "$new/notable.txt" ]]; then
            notable_added=$(comm -13 <(sort -u "$old/notable.txt") <(sort -u "$new/notable.txt") || true)
            if [[ -n "$notable_added" ]]; then
                echo "NOTABLE new processes (remote-access / shell-like):"
                echo "$notable_added"
            fi
        fi
        ;;
esac
