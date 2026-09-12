#!/usr/bin/env bash
# Re-encode project WAVs to Ogg Vorbis (q=4, ~128 kb/s). Used for beats/SFX.
# Requires ffmpeg. Godot will rewrite .import stubs on next editor open.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if ! command -v ffmpeg >/dev/null; then
	echo "ffmpeg not found" >&2
	exit 1
fi
find "$ROOT/assets/base/audio" -name '*.wav' -print0 | while IFS= read -r -d '' wav; do
	ogg="${wav%.wav}.ogg"
	echo "encode $ogg"
	ffmpeg -y -i "$wav" -c:a libvorbis -q:a 4 "$ogg"
done
echo "Done. Open the project in Godot 4.6 so .import files refresh."
