#!/usr/bin/env bash
# LAN trust module: detects gateway / DHCP / DNS hijack on networks you've seen before.
#
# Threat model: someone on your LAN (or an evil-twin AP) answers DHCP faster than
# the real router and hands you *their* gateway or DNS, silently MITM-ing traffic.
# The tell is not "a value exists" but "a value CHANGED for a network you know".
#
# State is keyed per-network. A network seen for the first time WARNS (and prints
# its full identity so you can eyeball the gateway and DNS you were handed); a
# network you already know only alerts if it CHANGES shape. That way roaming is
# visible but not indistinguishable from an attack.
#
# Every snapshot carries forward ALL networks ever seen (from a persistent
# baseline) and refreshes the ones currently connected. Without that, a
# home -> hotel -> home sequence would diff hotel-vs-home and report your own
# network as brand new every trip -- the exact false positive this module exists
# to avoid. See docs/ARCHITECTURE.md.
#
# Works unprivileged: NetworkManager already knows the DHCP lease options.
set -euo pipefail

BASELINE="${AFKWATCH_LAN_BASELINE:-$HOME/.local/share/afkwatch/lan-trust-baseline}"

# nmcli terse/get output escapes ':' and '\' with a backslash -- even for a
# single field. Strip one level of backslash escaping.
_unesc() { sed 's/\\\(.\)/\1/g'; }

_phys_devs() {
    # Physical carriers only. VPN/tunnel/dummy DNS legitimately churns.
    nmcli -g DEVICE,TYPE,STATE device 2>/dev/null \
        | _unesc \
        | awk -F: '$3=="connected" && ($2=="wifi"||$2=="ethernet") {print $1":"$2}'
}

# Distinct networks must never share a file. Sanitising alone is many-to-one
# ("Cafe/Guest" and "Cafe:Guest" both flatten to "Cafe_Guest"), so append a
# short digest of the raw identity bytes.
_key_for() {
    local raw="$1" safe h
    safe=$(printf '%s' "$raw" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-48)
    h=$(printf '%s' "$raw" | sha256sum | cut -c1-8)
    printf '%s-%s' "$safe" "$h"
}

_vendor() {
    local oui=/var/lib/ieee-data/oui.txt p
    [[ -f $oui ]] || return 0
    p=$(printf '%s' "${1:-}" | tr -d ':' | tr 'a-z' 'A-Z' | cut -c1-6)
    [[ -n $p ]] || return 0
    grep -m1 -i "^$p" "$oui" 2>/dev/null | sed 's/.*(base 16)[[:space:]]*//' || true
}

case "${1:-}" in
    name)        echo "lan-trust" ;;
    description) echo "Gateway/DHCP/DNS identity per network (rogue-DHCP + ARP-spoof detection)" ;;

    snapshot)
        out="$2"; mkdir -p "$BASELINE"

        # Fail loudly if NetworkManager can't be queried, rather than silently
        # recording "no networks" and letting a later diff report all-clear.
        if ! devs=$(_phys_devs); then
            echo "lan-trust: could not query NetworkManager for devices" >> "$out/.errors"
            devs=""
        fi

        while IFS=: read -r dev typ; do
            [[ -n ${dev:-} ]] || continue

            conn=$(nmcli -g GENERAL.CONNECTION device show "$dev" 2>/dev/null | _unesc || true)
            ssid=""; bssid=""; sec=""
            if [[ $typ == wifi ]]; then
                [[ -n $conn ]] && ssid=$(nmcli -g 802-11-wireless.ssid connection show "$conn" 2>/dev/null | _unesc || true)
                # Read each field on its own so an escaped colon can't shift columns.
                bssid=$(nmcli -g ACTIVE,BSSID device wifi list ifname "$dev" 2>/dev/null \
                        | awk -F: '$1=="yes"{sub(/^yes:/,""); print; exit}' | _unesc || true)
                sec=$(nmcli -g ACTIVE,SECURITY device wifi list ifname "$dev" 2>/dev/null \
                        | awk -F: '$1=="yes"{sub(/^yes:/,""); print; exit}' | _unesc || true)
            fi

            netid="${ssid:-${conn:-$dev}}"
            key=$(_key_for "$netid")

            gw=$(ip -4 route show default dev "$dev" 2>/dev/null | awk '{print $3; exit}' || true)
            gwmac=""
            if [[ -n $gw ]]; then
                timeout 2 ping -c1 -W1 -I "$dev" "$gw" >/dev/null 2>&1 || true
                gwmac=$(ip neigh show "$gw" dev "$dev" 2>/dev/null | awk '$2=="lladdr"{print $3; exit}' || true)
            fi
            gw6=$(ip -6 route show default dev "$dev" 2>/dev/null | awk '{print $3; exit}' || true)

            dhcp=$(nmcli -f DHCP4 device show "$dev" 2>/dev/null | sed 's/^DHCP4.OPTION\[[0-9]*\]:[[:space:]]*//' || true)
            dhcp_srv=$(printf '%s\n' "$dhcp" | awk -F' = ' '/^dhcp_server_identifier/{print $2; exit}')
            dhcp_dns=$(printf '%s\n' "$dhcp" | awk -F' = ' '/^domain_name_servers/{print $2; exit}')
            dhcp_rtr=$(printf '%s\n' "$dhcp" | awk -F' = ' '/^routers/{print $2; exit}')

            linkdns=$(nmcli -g IP4.DNS device show "$dev" 2>/dev/null | paste -sd' ' - || true)
            [[ -n ${linkdns// /} ]] || linkdns=$(resolvectl dns "$dev" 2>/dev/null | sed 's/^Link [0-9]* ([^)]*):[[:space:]]*//' || true)
            # IPv6 RDNSS is a separate hijack path from DHCPv4 -- record it too.
            linkdns6=$(nmcli -g IP6.DNS device show "$dev" 2>/dev/null | paste -sd' ' - || true)

            # network= is identity, not a monitored value (diff skips it).
            {
                echo "network=$netid"
                echo "type=$typ"
                echo "gateway_ip=${gw:-}"
                echo "gateway_mac=${gwmac:-}"
                echo "gateway_ip6=${gw6:-}"
                echo "bssid=${bssid:-}"
                echo "security=${sec:-}"
                echo "dhcp_server=${dhcp_srv:-}"
                echo "dhcp_routers=${dhcp_rtr:-}"
                echo "dhcp_dns=${dhcp_dns:-}"
                echo "link_dns=${linkdns:-}"
                echo "link_dns6=${linkdns6:-}"
            } > "$BASELINE/net-$key.kv.tmp"
            mv -f "$BASELINE/net-$key.kv.tmp" "$BASELINE/net-$key.kv"   # atomic: no torn reads
        done <<< "$devs"

        # Carry every known network into the snapshot, not just today's.
        cp -f "$BASELINE"/net-*.kv "$out/" 2>/dev/null || true
        (cd "$out" && for f in net-*.kv; do [[ -e $f ]] || continue
            awk -F= '$1=="network"{sub(/^network=/,""); print}' "$f"; done) > "$out/.networks" 2>/dev/null || true
        sort -u -o "$out/.networks" "$out/.networks" 2>/dev/null || true
        ;;

    diff)
        old="$2" new="$3"
        shopt -s nullglob
        for f in "$new"/net-*.kv; do
            base=$(basename "$f")
            o="$old/$base"
            net=$(awk -F= '$1=="network"{sub(/^network=/,""); print; exit}' "$f")
            [[ -n $net ]] || net="${base#net-}"

            if [[ ! -f $o ]]; then
                echo "** WARN ** [$net] NEW NETWORK joined since last snapshot - no prior baseline to compare"
                grep -v '^network=' "$f" | sed 's/^/     /'
                continue
            fi
            cmp -s "$o" "$f" && continue

            # Compare the UNION of keys: a key that vanished from the new file is
            # a change too, and iterating only the new file would miss it.
            declare -A OLDV=() NEWV=()
            while IFS='=' read -r k v; do [[ -n ${k:-} ]] && OLDV["$k"]="$v"; done < "$o"
            while IFS='=' read -r k v; do [[ -n ${k:-} ]] && NEWV["$k"]="$v"; done < "$f"

            for k in $(printf '%s\n' "${!OLDV[@]}" "${!NEWV[@]}" | sort -u); do
                [[ $k == network ]] && continue
                vold="${OLDV[$k]-<missing>}"; vnew="${NEWV[$k]-<missing>}"
                [[ "$vold" == "$vnew" ]] && continue
                case "$k" in
                    gateway_mac)
                        echo "** ALERT ** [$net] DEFAULT GATEWAY MAC CHANGED - possible ARP spoof / router swapped"
                        echo "     was: ${vold:-<none>} $(_vendor "$vold")"
                        echo "     now: ${vnew:-<none>} $(_vendor "$vnew")" ;;
                    dhcp_server)
                        echo "** ALERT ** [$net] DHCP SERVER CHANGED - possible rogue DHCP server"
                        echo "     was: ${vold:-<none>}  now: ${vnew:-<none>}" ;;
                    dhcp_dns|link_dns|link_dns6)
                        echo "** ALERT ** [$net] DNS SERVERS CHANGED ($k) - possible DNS hijack"
                        echo "     was: ${vold:-<none>}  now: ${vnew:-<none>}" ;;
                    dhcp_routers|gateway_ip|gateway_ip6)
                        echo "** ALERT ** [$net] gateway address changed ($k): ${vold:-<none>} -> ${vnew:-<none>}" ;;
                    security)
                        echo "** ALERT ** [$net] WIFI SECURITY CHANGED: ${vold:-<none>} -> ${vnew:-<none>} (evil-twin AP?)" ;;
                    bssid)
                        # Mesh/roaming makes this normal on multi-AP networks -- informational only.
                        echo "note: [$net] associated AP (BSSID) changed: ${vold:-<none>} -> ${vnew:-<none>} (normal when roaming between mesh APs)" ;;
                    type)
                        echo "** ALERT ** [$net] carrier type changed: ${vold:-<none>} -> ${vnew:-<none>}" ;;
                esac
            done
            unset OLDV NEWV
        done
        ;;
esac
