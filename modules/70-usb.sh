#!/usr/bin/env bash
# USB module: connected devices + recent USB events from kernel log.
set -euo pipefail

case "${1:-}" in
    name)        echo "usb" ;;
    description) echo "USB devices and insertion/removal events" ;;
    snapshot)
        out="$2"
        # Currently connected USB devices (vendor:product + description)
        lsusb 2>/dev/null | sort > "$out/lsusb.txt" || true
        # Block devices (catches USB drives mounted)
        lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL,VENDOR 2>/dev/null > "$out/lsblk.txt" || true
        # Mount table (USB drives etc.)
        mount | sort > "$out/mounts.txt" || true
        # USB events from kernel journal (last 24h)
        journalctl -k --since "24 hours ago" --no-pager 2>/dev/null \
            | grep -iE 'usb [0-9]+-[0-9]+|new (full|high|low)-speed USB|USB disconnect' \
            | tail -n 100 > "$out/usb_events.log" || true
        ;;
    diff)
        old="$2" new="$3"
        if [[ -f "$old/lsusb.txt" && -f "$new/lsusb.txt" ]]; then
            added=$(comm -13 "$old/lsusb.txt" "$new/lsusb.txt" || true)
            removed=$(comm -23 "$old/lsusb.txt" "$new/lsusb.txt" || true)
            [[ -n "$added" ]]   && { echo "USB devices PLUGGED IN:";   echo "$added" | sed 's/^/  /'; }
            [[ -n "$removed" ]] && { echo "USB devices removed:";       echo "$removed" | sed 's/^/  /'; }
        fi
        if [[ -f "$old/mounts.txt" && -f "$new/mounts.txt" ]]; then
            m_added=$(comm -13 "$old/mounts.txt" "$new/mounts.txt" || true)
            [[ -n "$m_added" ]] && { echo "NEW mounts:"; echo "$m_added" | sed 's/^/  /'; }
        fi
        # New entries in the USB kernel journal between snapshots
        if [[ -f "$old/usb_events.log" && -f "$new/usb_events.log" ]]; then
            new_events=$(comm -13 <(sort "$old/usb_events.log") <(sort "$new/usb_events.log") || true)
            [[ -n "$new_events" ]] && { echo "USB kernel events while away:"; echo "$new_events" | head -10 | sed 's/^/  /'; }
        fi
        ;;
esac
