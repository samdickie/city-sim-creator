#!/bin/bash
# Dev tool: film a short promotional video of the game (see scripts/dev_promo.gd).
#
#   tools/make_promo.sh [outdir] [--draft] [--only=skyline,night]
#
# Opens a Godot window, grows the City example from the empty map, flies round
# the finished city and saves every frame to outdir/frames (default
# screenshots/promo), then joins them into outdir/troon_city_promo.mp4 with
# ffmpeg: 1920x1080, 30 frames a second, H.264 with a silent sound track, which
# is what X (Twitter) takes. About 10 minutes. --draft films at 960x540 (quicker).
# Don't cover or minimise the window while it runs.
# Set GODOT=/path/to/Godot if it isn't in ~/Downloads/Godot.app.
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
OUT="screenshots/promo"
ONLY=""
SIZE="1920x1080"
for arg in "$@"; do
	case "$arg" in
		--only=*) ONLY="${arg#--only=}" ;;
		--draft) SIZE="960x540" ;;
		-h|--help) sed -n '2,13p' "$0"; exit 0 ;;
		*) OUT="$arg" ;;
	esac
done
mkdir -p "$OUT/frames"
OUT="$(cd "$OUT" && pwd)"
rm -f "$OUT"/frames/f*.jpg
LOG="$OUT/godot.log"

ARGS=(--path . --windowed -- "--promo=$OUT/frames" "--promo-size=$SIZE")
if [ -n "$ONLY" ]; then
	ARGS+=("--promo-only=$ONLY")
fi

START=$(date +%s)
"$GODOT" "${ARGS[@]}" 2>&1 | tee "$LOG"
echo "Filmed in $(( $(date +%s) - START )) s"

grep -nE "SCRIPT ERROR|Parse Error" "$LOG" && exit 1

# H.264, yuv420p, a silent AAC track and the index at the front: plays anywhere.
ffmpeg -y -loglevel error -framerate 30 -i "$OUT/frames/f%05d.jpg" \
	-f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 -shortest \
	-c:v libx264 -preset slow -crf 17 -maxrate 16M -bufsize 32M -vf "scale=in_range=full:out_range=tv,format=yuv420p" -color_range tv -profile:v high \
	-r 30 -c:a aac -b:a 128k -movflags +faststart "$OUT/troon_city_promo.mp4" || exit 1
ls -lh "$OUT/troon_city_promo.mp4"
