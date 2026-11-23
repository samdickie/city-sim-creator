#!/bin/bash
# Builds the downloadable game for Mac and Windows into builds/ (git-ignored):
#   builds/SiliconCity-mac.zip       the .app (Apple Silicon and Intel)
#   builds/SiliconCity-windows.zip   Silicon City.exe (64-bit)
# Uses export_presets.cfg. Needs Godot's export templates for this Godot version
# (Editor > Manage Export Templates, or the .tpz from Godot's GitHub releases).
# Takes a few minutes. Set GODOT=/path/to/Godot if it isn't in ~/Downloads/Godot.app.
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$HOME/Downloads/Godot.app/Contents/MacOS/Godot}"
rm -rf builds
mkdir -p builds/windows

echo "== macOS"
"$GODOT" --headless --path . --export-release "macOS" "builds/Silicon City.zip" 2>&1 | tee builds/mac.log
mv "builds/Silicon City.zip" builds/SiliconCity-mac.zip
cp tools/build_readme.txt "builds/Read me.txt"
(cd builds && zip -q SiliconCity-mac.zip "Read me.txt" && rm "Read me.txt")

echo "== Windows"
"$GODOT" --headless --path . --export-release "Windows" "builds/windows/Silicon City.exe" 2>&1 | tee builds/windows.log
cp tools/build_readme.txt "builds/windows/Read me.txt"
(cd builds/windows && zip -qr ../SiliconCity-windows.zip .)

# Godot prints ERROR lines when an export goes wrong but doesn't always fail.
if grep -q "ERROR" builds/mac.log builds/windows.log; then
	echo "Export reported errors: see builds/mac.log and builds/windows.log"
	exit 1
fi
ls -lh builds/*.zip
