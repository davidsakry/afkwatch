#!/usr/bin/env bash
# Files module: integrity hashes of sensitive files. Detects modifications.
set -euo pipefail

# Watched files. Override by setting AFKWATCH_WATCHED_FILES in the config (newline-separated).
DEFAULT_WATCHED=(
    "$HOME/.bashrc"
    "$HOME/.bash_profile"
    "$HOME/.profile"
    "$HOME/.zshrc"
    "$HOME/.zshenv"
    "$HOME/.ssh/authorized_keys"
    "$HOME/.ssh/config"
    "$HOME/.ssh/known_hosts"
    "$HOME/.gitconfig"
    "$HOME/.bash_history"
    "/etc/passwd"
    "/etc/group"
    "/etc/sudoers"
    "/etc/hosts"
    "/etc/hostname"
    "/etc/resolv.conf"
    "/etc/pam.d/sshd"
    "/etc/ssh/sshd_config"
)

# Watched directories — we hash every file inside (one level, non-recursive by default)
DEFAULT_WATCHED_DIRS=(
    "$HOME/.ssh"
    "$HOME/.config/autostart"
    "/etc/sudoers.d"
    "/etc/cron.d"
    "/etc/cron.daily"
    "/etc/cron.hourly"
)

case "${1:-}" in
    name)        echo "files" ;;
    description) echo "Integrity hashes of shell rc, ssh config, /etc essentials" ;;
    snapshot)
        out="$2"
        : > "$out/hashes.txt"
        for f in "${DEFAULT_WATCHED[@]}"; do
            if [[ -r "$f" ]]; then
                sha256sum "$f" 2>/dev/null >> "$out/hashes.txt" || true
            fi
        done
        for d in "${DEFAULT_WATCHED_DIRS[@]}"; do
            [[ -d "$d" && -r "$d" ]] || continue
            find "$d" -maxdepth 1 -type f -readable -exec sha256sum {} \; 2>/dev/null >> "$out/hashes.txt" || true
        done
        sort -k2 "$out/hashes.txt" -o "$out/hashes.txt"
        ;;
    diff)
        old="$2" new="$3"
        [[ -f "$old/hashes.txt" && -f "$new/hashes.txt" ]] || exit 0
        # Files where the hash changed
        join -j 2 -o 1.2,1.1,2.1 "$old/hashes.txt" "$new/hashes.txt" \
            | awk '$2 != $3 { print $1 }' > /tmp/afkwatch_changed.$$
        if [[ -s /tmp/afkwatch_changed.$$ ]]; then
            echo "MODIFIED files:"
            sed 's/^/  /' /tmp/afkwatch_changed.$$
        fi
        rm -f /tmp/afkwatch_changed.$$
        # Files present in new but not old (newly created)
        added=$(comm -13 <(awk '{print $2}' "$old/hashes.txt") <(awk '{print $2}' "$new/hashes.txt") || true)
        [[ -n "$added" ]] && { echo "NEW files in watched paths:"; echo "$added" | sed 's/^/  /'; }
        # Files present in old but not new (removed)
        removed=$(comm -23 <(awk '{print $2}' "$old/hashes.txt") <(awk '{print $2}' "$new/hashes.txt") || true)
        [[ -n "$removed" ]] && { echo "REMOVED files:"; echo "$removed" | sed 's/^/  /'; }
        ;;
esac
