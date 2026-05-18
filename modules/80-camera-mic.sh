#!/usr/bin/env bash
# Camera/mic module: detect access to webcam and audio devices.
set -euo pipefail

case "${1:-}" in
    name)        echo "camera-mic" ;;
    description) echo "Webcam and microphone access (live + recent)" ;;
    snapshot)
        out="$2"
        # Who currently has /dev/video* or /dev/snd/* open
        : > "$out/lsof_av.txt"
        for dev in /dev/video* /dev/snd/* /dev/dvb/* ; do
            [[ -e "$dev" ]] || continue
            lsof "$dev" 2>/dev/null >> "$out/lsof_av.txt" || true
        done
        # PulseAudio / PipeWire client list (who's holding an audio stream)
        if command -v pactl >/dev/null 2>&1; then
            pactl list source-outputs 2>/dev/null > "$out/audio_capture.txt" || true
            pactl list clients 2>/dev/null | grep -E 'application.name|application.process.binary' > "$out/audio_clients.txt" || true
        fi
        # Recent uvcvideo (webcam driver) events in the kernel log
        journalctl -k --since "24 hours ago" --no-pager 2>/dev/null \
            | grep -iE 'uvcvideo|snd_|audio' | tail -n 50 > "$out/av_kernel.log" || true
        # Snapshot the current AV device-access count (small heuristic)
        wc -l < "$out/lsof_av.txt" > "$out/active_count.txt" || true
        ;;
    diff)
        old="$2" new="$3"
        # New processes that have an AV device open
        if [[ -f "$old/lsof_av.txt" && -f "$new/lsof_av.txt" ]]; then
            new_proc=$(comm -13 <(sort "$old/lsof_av.txt") <(sort "$new/lsof_av.txt") | grep -v '^COMMAND' || true)
            [[ -n "$new_proc" ]] && { echo "NEW camera/mic access (lsof):"; echo "$new_proc" | head -10; }
        fi
        # New audio capture streams
        if [[ -f "$old/audio_capture.txt" && -f "$new/audio_capture.txt" ]]; then
            # Compare source-output indices — new ones since baseline
            old_n=$(grep -c "^Source Output" "$old/audio_capture.txt" 2>/dev/null || echo 0)
            new_n=$(grep -c "^Source Output" "$new/audio_capture.txt" 2>/dev/null || echo 0)
            if (( new_n > old_n )); then
                echo "new audio capture stream(s) (was $old_n, now $new_n):"
                grep -A2 'application.name\|application.process.binary' "$new/audio_capture.txt" | head -10
            fi
        fi
        # New kernel log entries for AV
        if [[ -f "$old/av_kernel.log" && -f "$new/av_kernel.log" ]]; then
            new_evt=$(comm -13 <(sort "$old/av_kernel.log") <(sort "$new/av_kernel.log") || true)
            [[ -n "$new_evt" ]] && { echo "AV kernel events while away:"; echo "$new_evt" | head -10; }
        fi
        ;;
esac
