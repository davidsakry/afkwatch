#!/usr/bin/env bash
# Logins module: who logged in (local, SSH), failed attempts, current sessions.
set -euo pipefail

case "${1:-}" in
    name)        echo "logins" ;;
    description) echo "User logins, SSH sessions, failed auth attempts" ;;
    snapshot)
        out="$2"
        last -F -n 50 > "$out/last.txt" 2>/dev/null || true
        last -F -x -n 20 > "$out/last_x.txt" 2>/dev/null || true  # includes shutdown/reboot
        who > "$out/who.txt" 2>/dev/null || true
        w -h > "$out/w.txt" 2>/dev/null || true
        # Failed logins (needs root for /var/log/btmp on most distros; ignore if denied)
        lastb -F -n 50 > "$out/lastb.txt" 2>/dev/null || echo "(needs root)" > "$out/lastb.txt"
        # SSH journal for the last 24h
        journalctl _COMM=sshd --since "24 hours ago" --no-pager 2>/dev/null \
            | tail -n 200 > "$out/sshd.log" || true
        # Auth log for the last 24h
        journalctl _SYSTEMD_UNIT=systemd-logind.service --since "24 hours ago" --no-pager 2>/dev/null \
            | tail -n 100 > "$out/logind.log" || true
        ;;
    diff)
        old="$2" new="$3"
        # New entries in last.txt (lines in new that aren't in old)
        if [[ -f "$old/last.txt" && -f "$new/last.txt" ]]; then
            new_logins=$(comm -13 <(sort "$old/last.txt") <(sort "$new/last.txt") | grep -v '^$' | grep -v '^wtmp begins' || true)
            [[ -n "$new_logins" ]] && { echo "new login records:"; echo "$new_logins" | head -20; }
        fi
        # Failed auth attempts that are new
        if [[ -f "$old/lastb.txt" && -f "$new/lastb.txt" ]]; then
            new_fails=$(comm -13 <(sort "$old/lastb.txt") <(sort "$new/lastb.txt") | grep -v '^$' | grep -v '^(needs root)' | grep -v '^btmp begins' || true)
            [[ -n "$new_fails" ]] && { echo "FAILED auth attempts:"; echo "$new_fails" | head -10; }
        fi
        # SSH events
        if [[ -f "$old/sshd.log" && -f "$new/sshd.log" ]]; then
            # Filter for "Accepted", "Failed password", "session opened"
            sshd_new=$(comm -13 <(sort "$old/sshd.log") <(sort "$new/sshd.log") \
                | grep -E 'Accepted|Failed password|session opened|Invalid user' || true)
            [[ -n "$sshd_new" ]] && { echo "sshd events:"; echo "$sshd_new" | head -10; }
        fi
        # Currently-logged-in users that weren't before
        if [[ -f "$old/who.txt" && -f "$new/who.txt" ]]; then
            new_sessions=$(comm -13 <(sort "$old/who.txt") <(sort "$new/who.txt") | grep -v '^$' || true)
            [[ -n "$new_sessions" ]] && { echo "new active sessions:"; echo "$new_sessions"; }
        fi
        ;;
esac
