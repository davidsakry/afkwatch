# afkwatch architecture

## One-paragraph summary

`afkwatch` is a state-diffing intrusion-detection tool for Linux desktops. It takes "snapshots" of suspicious state surfaces (logins, processes, network sockets, file integrity, scheduled tasks, USB devices, AV-device access, installed packages), stores them on disk, and shows you what changed between any two points in time. The intended workflow is `arm` before you leave your machine and `check` when you return — but the same primitives also support periodic hourly snapshotting via a systemd user timer, ad-hoc snapshots, and pairwise diffs.

## Design goals

1. **No daemon required.** v0.1 is plain shell scripts you invoke manually or from a systemd timer. No long-running process, no privileged service.
2. **Lightweight.** Everything is shell + standard userspace tools (`ps`, `ss`, `lsof`, `last`, `journalctl`, `sha256sum`, `lsusb`, `pactl`, `dpkg-query`). Snapshots are plain text files in `~/.local/share/afkwatch/snapshots/`.
3. **Pluggable modules.** Each detection surface lives in its own self-contained script under `modules/`. To extend afkwatch, drop a new `modules/NN-yourthing.sh` in — no editing of core code.
4. **Boring storage.** Snapshots are diffable text files in nested directories. You can `cd` in and read them. No database, no binary format.
5. **Userspace first.** Everything works without root. Some detections improve with root (e.g. `lastb`, `/etc/shadow`, system iptables) but the default install assumes none.

## Module interface

Every module is an executable script (typically bash) at `modules/<NN>-<name>.sh` that responds to four subcommands:

| Subcommand                  | Stdout                                | Stderr / exit |
|-----------------------------|---------------------------------------|---------------|
| `name`                      | A short identifier (e.g. `processes`) | exit 0        |
| `description`               | One-line human description            | exit 0        |
| `snapshot <outdir>`         | (nothing)                             | Writes state files into `outdir`. May write errors to `outdir/.errors` (auto-collected by the runner). |
| `diff <old_dir> <new_dir>`  | Human-readable findings, or nothing if no change. | Exit 0 either way. |

The `NN-` prefix sorts modules in the report; the rest of the filename is cosmetic.

## Snapshot layout on disk

```
~/.local/share/afkwatch/
├── .armed                              # path of the current "armed" baseline
└── snapshots/
    ├── 20260517-091500_afk/
    │   ├── .timestamp
    │   ├── .label
    │   ├── logins/{last.txt, who.txt, ...}
    │   ├── processes/{procs.txt, ...}
    │   ├── network/{listening.txt, ...}
    │   └── ...
    └── 20260517-110200_check/
        └── ...
```

## Why "diff snapshots" instead of a real-time daemon?

Real-time monitoring (`auditd`, `inotify`, eBPF) is more powerful but:
- Needs root and careful rule configuration.
- Produces firehose-volume logs you have to triage.
- Is hard to package portably.

State diffing is coarse but reliably captures the *outcome* of intrusion (a new listener, a modified `authorized_keys`, a new cron job) without depending on having watched it happen live. It's also easy to reason about and easy to extend. v0.1 is intentionally this layer; v0.2+ can grow optional `auditd`/`inotify` modules that hook into the same module interface.

## Extending afkwatch

To add a new module:

1. Copy `modules/90-packages.sh` as a starting point.
2. Implement `snapshot` (write whatever state files you like into `$2`).
3. Implement `diff` (compare `$2` and `$3`, print human-readable findings; empty output = no change).
4. `chmod +x` and put it in `modules/`. Done — the CLI auto-discovers it.

Module ideas for v0.2+:
- `dns` — `/etc/resolv.conf` + recent DNS query patterns
- `kernel` — loaded kernel modules (`lsmod`), kernel command line
- `browser` — newly-installed browser extensions
- `shell_history` — diff of `.bash_history` / `.zsh_history`
- `clipboard` — clipboard manager history changes
- `screenshot` — `import` a desktop screenshot at snapshot time (visual baseline)
- `auditd` — bridge to `ausearch` for kernel-level FS events
