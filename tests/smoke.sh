#!/usr/bin/env bash
# Minimal smoke test: take two snapshots and confirm the CLI runs end-to-end.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")"/.. && pwd)"
export AFKWATCH_DATA="$(mktemp -d)"
trap 'rm -rf "$AFKWATCH_DATA"' EXIT

echo "data dir: $AFKWATCH_DATA"

"$HERE/afkwatch" modules
echo
"$HERE/afkwatch" snapshot baseline > /dev/null
sleep 1
"$HERE/afkwatch" snapshot followup > /dev/null
echo
"$HERE/afkwatch" list
echo
"$HERE/afkwatch" diff

echo
echo "smoke test passed."
