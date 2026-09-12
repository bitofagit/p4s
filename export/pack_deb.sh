#!/usr/bin/env bash
# Build a simple amd64 .deb from a Godot Linux export.
# Prerequisites: Godot 4.6 export already written to build/linux/p4s-linux-x86_64.x86_64
#                dpkg-deb on the PATH (Debian/Ubuntu).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/linux/p4s-linux-x86_64.x86_64"
if [[ ! -f "$BIN" ]]; then
	echo "Missing $BIN — export Linux Desktop x86_64 first." >&2
	exit 1
fi
VER="$(grep -E '^config/version=' "$ROOT/project.godot" | head -1 | cut -d= -f2 | tr -d '"')"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/DEBIAN" \
	"$STAGE/usr/games" \
	"$STAGE/usr/share/applications" \
	"$STAGE/usr/share/pixmaps" \
	"$STAGE/usr/share/doc/p4s"
cp "$BIN" "$STAGE/usr/games/p4s"
chmod 755 "$STAGE/usr/games/p4s"
# Sidecar .pck if export did not embed it
if [[ -f "$ROOT/build/linux/p4s-linux-x86_64.pck" ]]; then
	mkdir -p "$STAGE/usr/share/p4s"
	cp "$ROOT/build/linux/p4s-linux-x86_64.pck" "$STAGE/usr/share/p4s/"
fi
cp "$ROOT/export/p4s.desktop" "$STAGE/usr/share/applications/"
if [[ -f "$ROOT/icon.svg" ]]; then
	cp "$ROOT/icon.svg" "$STAGE/usr/share/pixmaps/p4s.svg"
fi
cat > "$STAGE/DEBIAN/control" <<EOF
Package: p4s
Version: ${VER:-0.9.5.28}
Section: games
Priority: optional
Architecture: amd64
Maintainer: P4S opencore <p4s@localhost>
Depends: libgl1, libx11-6, libxcursor1, libxinerama1, libxrandr2, libxi6, libasound2
Description: Permaculture 4 Squares (open-core)
 Turn-based permaculture farm simulator (Godot 4.6).
EOF
OUT="$ROOT/build/linux/p4s_${VER:-0.9.5.28}_amd64.deb"
mkdir -p "$ROOT/build/linux"
dpkg-deb --build "$STAGE" "$OUT"
echo "Wrote $OUT"
