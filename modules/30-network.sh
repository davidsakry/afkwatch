#!/usr/bin/env bash
# Network module: listening ports + established connections.
set -euo pipefail

case "${1:-}" in
    name)        echo "network" ;;
    description) echo "Listening ports and remote connections" ;;
    snapshot)
        out="$2"
        # Listening sockets (TCP + UDP), with process if visible.
        # Skip the header row so it doesn't get treated as a diff.
        ss -tunlp 2>/dev/null | tail -n +2 | sort > "$out/listening.txt" || true
        # Established TCP connections (skip header)
        ss -tnp state established 2>/dev/null | tail -n +2 | sort > "$out/established.txt" || true
        # ARP table (devices on the LAN — useful context)
        ip neigh 2>/dev/null | sort > "$out/neigh.txt" || true
        # Routing table (defensive — detect a sneaky route added)
        ip route 2>/dev/null | sort > "$out/route.txt" || true
        # iptables/nftables rules (root-only output mostly; we record what we can)
        (command -v nft >/dev/null && nft list ruleset 2>/dev/null) > "$out/nft.txt" || true
        ;;
    diff)
        old="$2" new="$3"
        # New listening ports
        if [[ -f "$old/listening.txt" && -f "$new/listening.txt" ]]; then
            added=$(comm -13 "$old/listening.txt" "$new/listening.txt" || true)
            [[ -n "$added" ]] && { echo "NEW listening sockets:"; echo "$added" | head -20; }
        fi
        # New established connections (filter noise: keep only remote-initiated or non-localhost)
        if [[ -f "$old/established.txt" && -f "$new/established.txt" ]]; then
            added=$(comm -13 "$old/established.txt" "$new/established.txt" | grep -v '127\.0\.0\.1\|::1' || true)
            [[ -n "$added" ]] && { echo "new established connections (non-loopback):"; echo "$added" | head -20; }
        fi
        # Route table changes
        if [[ -f "$old/route.txt" && -f "$new/route.txt" ]]; then
            r_added=$(comm -13 "$old/route.txt" "$new/route.txt" || true)
            r_removed=$(comm -23 "$old/route.txt" "$new/route.txt" || true)
            [[ -n "$r_added" ]] && { echo "ADDED routes:"; echo "$r_added"; }
            [[ -n "$r_removed" ]] && { echo "REMOVED routes:"; echo "$r_removed"; }
        fi
        ;;
esac
