#!/bin/bash
# Dev tool: build the example cities in the game menu and save them to
# examples/<id>.json (see scripts/dev_examples.gd).
#
#   tools/make_examples.sh [picture dir] [--only=city]
#
# Opens a 1600x1000 Godot window, builds each city with the game's own tools and
# rules from a fixed seed, saves it, loads it back as a check, and saves pictures
# of it to the picture dir (default screenshots/examples). About 3 minutes.
# Set GODOT=/path/to/Godot if it isn't in ~/Downloads/Godot.app.
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
OUT="screenshots/examples"
ONLY=""
for arg in "$@"; do
	case "$arg" in
		--only=*) ONLY="${arg#--only=}" ;;
		-h|--help) sed -n '2,10p' "$0"; exit 0 ;;
		*) OUT="$arg" ;;
	esac
done
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
LOG="$OUT/godot.log"

ARGS=(--path . --windowed --resolution 1600x1000 -- "--examples=$OUT")
if [ -n "$ONLY" ]; then
	ARGS+=("--examples-only=$ONLY")
fi

START=$(date +%s)
"$GODOT" "${ARGS[@]}" 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
echo "Took $(( $(date +%s) - START )) s. Pictures in $OUT"

PROBLEMS=$(grep -nE "ERROR|WARNING|SCRIPT ERROR|Parse Error|at: " "$LOG" || true)
if [ -n "$PROBLEMS" ]; then
	echo
	echo "Godot reported problems:"
	echo "$PROBLEMS"
	exit 1
fi
exit "$STATUS"
