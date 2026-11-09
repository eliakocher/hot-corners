#!/bin/bash
# Builds HotCorners.app (Apple Silicon only).   ./build.sh [--install] 
#   --install  copies it to ~/Applications/HotCorners.app and launches it
set -euo pipefail
root=$(cd "$(dirname "$0")" && pwd)
app=$root/HotCorners.app

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/Info.plist" "$app/Contents/Info.plist"
cp "$root/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 "$root"/*.swift -o "$app/Contents/MacOS/HotCorners"
codesign --force --sign - "$app"
echo "built $app"

if [[ " $* " == *" --install "* ]]; then
	pkill -x HotCorners || true
	mkdir -p "$HOME/Applications"
	rm -rf "$HOME/Applications/HotCorners.app"
	cp -R "$app" "$HOME/Applications/"
	open "$HOME/Applications/HotCorners.app"
	echo "installed and launched ~/Applications/HotCorners.app"
fi
