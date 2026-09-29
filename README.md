# afkwatch

**Lightweight Linux "did anyone touch my machine while I was away?" monitor.**

`afkwatch` snapshots the parts of your system that matter for intrusion detection — logins, running processes, listening ports, file integrity, cron jobs, USB devices, webcam/mic access, installed packages — and tells you what changed between any two points in time.

The intended use is dead simple:

```bash
afkwatch arm     # before you step away from your computer
afkwatch check   # when you return
```

If something happened in between — someone logged in over SSH, a new process started listening on a port, your `~/.ssh/authorized_keys` got modified, a USB drive was plugged in, your webcam was opened — `afkwatch check` will show it. If nothing changed, you get a single `[clean]` line.

It's also useful as a periodic baseline tool via the included systemd user timer (hourly snapshots, kept in history).

## Why not just use ClamAV / rkhunter / chkrootkit?

Those are signature-based scanners — they're great for matching *known* malware, but weak at noticing that *your specific machine* changed in a suspicious way (a new SSH session, a fresh listener on :4444, a modified authorized_keys file). afkwatch is the complementary tool: it cares about *change relative to your normal*, not about matching a virus database. Run all of them if you like.

## What it watches

| Module        | What it captures |
|---------------|------------------|
| `logins`      | `last`, `lastb`, `who`, sshd journal events |
| `processes`   | Process tree (user + command) — flags new processes, especially shell/remote-access-flavored ones |
| `network`     | Listening ports (`ss -tunlp`), established connections, route table |
| `lan-trust`   | Per-network gateway MAC, DHCP server, DNS and AP identity — catches rogue DHCP servers, ARP spoofing, DNS hijack and evil-twin APs |
| `files`       | sha256 of shell rc files, `~/.ssh/*`, `/etc/passwd`, `/etc/sudoers`, etc. |
| `cron`        | User crontab, `/etc/cron.*`, systemd timers (user + system) |
| `autostart`   | `~/.config/autostart`, user systemd units, enabled system services |
| `usb`         | `lsusb`, block devices, mount table, USB kernel events |
| `camera-mic`  | `lsof` on `/dev/video*` + `/dev/snd/*`, PulseAudio capture streams, uvcvideo kernel events |
| `packages`    | apt, snap, flatpak — installed/removed |

Each module is a single self-contained script in `modules/`. To add your own surface, drop in a `modules/NN-yourthing.sh` — see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Install

```bash
git clone https://github.com/davidsakry/afkwatch.git
cd afkwatch
./install.sh                  # symlinks bin into ~/.local/bin
./install.sh --with-timer     # also installs hourly snapshot systemd timer
```

Requires only standard Linux userspace tools — `bash`, `ps`, `ss`, `lsof`, `last`, `journalctl`, `sha256sum`, `lsusb`, `lsblk`. Tested on Linux Mint 22 / Ubuntu 24 family; should work on any glibc-based Linux with systemd.

No root required. A few detections (e.g. failed-login records from `/var/log/btmp`, system iptables rules) are richer with root but degrade gracefully without.

## Usage

```bash
afkwatch arm                 Take an AFK baseline snapshot. Run before stepping away.
afkwatch check               Take a new snapshot and diff against the AFK baseline.
afkwatch snapshot [label]    Take a snapshot (optionally labeled). Stored in history.
afkwatch diff [a] [b]        Diff two snapshots (defaults to the last two).
afkwatch list                List all stored snapshots.
afkwatch modules             List installed modules.
afkwatch prune [N=50]        Keep only the most recent N snapshots.
afkwatch version
```

### Example session

```
$ afkwatch arm
[arming] taking AFK baseline snapshot...
[armed] baseline: 20260517-091500_afk
  run 'afkwatch check' when you return to see what happened.

... [you go to lunch, someone walks up to your computer] ...

$ afkwatch check
[checking] taking current snapshot...
afkwatch diff
  baseline: 20260517-091500_afk
  current:  20260517-104200_check

[logins] User logins, SSH sessions, failed auth attempts
  new login records:
    david    pts/1        :0               Sun May 17 10:38   still logged in

[network] Listening ports and remote connections
  NEW listening sockets:
    tcp   LISTEN 0  5   *:4444   *:*    users:(("nc",pid=12345,fd=3))

[files] Integrity hashes of shell rc and ssh config
  MODIFIED files:
    /home/david/.ssh/authorized_keys

[usb] USB devices and insertion/removal events
  USB devices PLUGGED IN:
    Bus 001 Device 014: ID 0781:5567 SanDisk Cruzer Blade

[4 module(s) reported changes]
```

## Data location

Snapshots live under `~/.local/share/afkwatch/snapshots/` as plain text files in nested directories — you can `cd` in and read them with any tool. Config (optional) is `~/.config/afkwatch/afkwatch.conf`.

To remove everything:

```bash
./uninstall.sh
rm -rf ~/.local/share/afkwatch
```

## Limitations / honest caveats

- **State diffing, not real-time monitoring.** If an attacker entered, did something, and cleaned up perfectly before you ran `check`, afkwatch won't see it. For that you want `auditd` or eBPF-based tools. afkwatch is designed to catch the much more common case: someone (or something) leaving evidence behind.
- **Most modules don't need root, but some signals improve with it** — failed-login records from `/var/log/btmp`, system iptables/nftables rules, `/etc/shadow` integrity. The tool runs as your user by default; if you want broader coverage, install it for root too.
- **Snapshots include hashes and process lists** — not necessarily sensitive, but treat them like logs.

## Roadmap

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the module interface and ideas for v0.2+ modules (DNS, kernel modules, browser extensions, shell history diffs, screenshot baselines, `auditd` integration).

## License

MIT. See [LICENSE](LICENSE).
