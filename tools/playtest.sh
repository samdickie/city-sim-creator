#!/bin/bash
# Dev tool: play a new game with real mouse and keyboard events, check every step
# and save pictures along the way (see scripts/dev_playtest.gd).
#
#   tools/playtest.sh [outdir]
#
# Opens the game in its normal window (maximized, full Retina resolution, like
# real play), starts a blank game, builds a few streets from the Build menu with
# mouse drags, runs a year at Fast, tries the HUD, map views, taxes, save and
# load, every keyboard shortcut and the camera controls, then quits. Prints a
# PASS or FAIL line per check; fails if any check fails or Godot reports errors.
# Takes about 2-3 minutes. Don't move the mouse over its window while it runs.
# Set GODOT=/path/to/Godot if it isn't in ~/Downloads/Godot.app.
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
OUT="${1:-screenshots/playtest}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
LOG="$OUT/godot.log"

START=$(date +%s)
"$GODOT" --path . -- "--playtest=$OUT" 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
echo "Took $(( $(date +%s) - START )) s. Pictures in $OUT"

PROBLEMS=$(grep -nE "ERROR|WARNING|SCRIPT ERROR|Parse Error|at: |FAIL" "$LOG" || true)
if [ -n "$PROBLEMS" ]; then
	echo
	echo "Problems:"
	echo "$PROBLEMS"
	exit 1
fi
exit "$STATUS"
