#!/bin/bash
# Builds build/HotCorners.app (universal: Apple Silicon + Intel).   ./build.sh [--install] [--zip]
#   --install  copies it to ~/Applications/HotCorners.app and launches it
#   --zip      also writes build/HotCorners.zip, ready to hand to someone
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
app=$root/build/HotCorners.app
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$root/Info.plist" "$app/Contents/Info.plist"
for arch in arm64 x86_64; do
	swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" "$root"/*.swift -o "$tmp/HotCorners-$arch"
done
lipo -create "$tmp"/HotCorners-* -output "$app/Contents/MacOS/HotCorners"
codesign --force --sign - "$app"
echo "built $app"

if [[ " $* " == *" --zip "* ]]; then
	rm -f "$root/build/HotCorners.zip"
	ditto -c -k --keepParent "$app" "$root/build/HotCorners.zip"
	echo "zipped $root/build/HotCorners.zip"
fi

if [[ " $* " == *" --install "* ]]; then
	pkill -x HotCorners || true
	mkdir -p "$HOME/Applications"
	rm -rf "$HOME/Applications/HotCorners.app"
	cp -R "$app" "$HOME/Applications/"
	open "$HOME/Applications/HotCorners.app"
	echo "installed and launched ~/Applications/HotCorners.app"
fi
