#!/bin/bash
# Dev tool: build a demo town and save screenshots of it (see scripts/dev_shots.gd).
#
#   tools/screenshots.sh [outdir] [--only=04_cbd,09_night] [--perf]
#
# --perf takes no pictures: it prints a table of what each part of the picture
# costs to draw (hide it, time it) at three views instead.
# Opens a 1600x1000 Godot window (a real renderer is needed: --headless draws
# nothing), builds the same town every time, saves the PNGs to outdir (default
# screenshots/) and quits. The Godot output is saved to outdir/godot.log; any
# errors or warnings in it are listed at the end and make the script fail.
# Set GODOT=/path/to/Godot if it isn't in ~/Downloads/Godot.app.
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
OUT="screenshots"
ONLY=""
PERF=""
for arg in "$@"; do
	case "$arg" in
		--only=*) ONLY="${arg#--only=}" ;;
		--perf) PERF=1 ;;
		-h|--help) sed -n '2,13p' "$0"; exit 0 ;;
		*) OUT="$arg" ;;
	esac
done
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
LOG="$OUT/godot.log"

ARGS=(--path . --windowed --resolution 1600x1000 -- "--shots=$OUT")
if [ -n "$ONLY" ]; then
	ARGS+=("--shots-only=$ONLY")
fi
if [ -n "$PERF" ]; then
	ARGS+=("--shots-perf")
fi

START=$(date +%s)
"$GODOT" "${ARGS[@]}" 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
echo "Took $(( $(date +%s) - START )) s. Screenshots in $OUT"

PROBLEMS=$(grep -nE "ERROR|WARNING|SCRIPT ERROR|Parse Error|at: " "$LOG" || true)
if [ -n "$PROBLEMS" ]; then
	echo
	echo "Godot reported problems:"
	echo "$PROBLEMS"
	exit 1
fi
exit "$STATUS"
