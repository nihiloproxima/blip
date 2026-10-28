#!/usr/bin/env bash
# Construit build/Blip.app (release universelle arm64 + x86_64, signature ad hoc).
# `--install` la copie dans /Applications et la (re)lance.
set -euo pipefail
cd "$(dirname "$0")/.."

arch=(--arch arm64 --arch x86_64)
swift build -c release "${arch[@]}"
bin="$(swift build -c release "${arch[@]}" --show-bin-path)/Blip"

app=build/Blip.app
rm -rf "$app" build/AppIcon.iconset
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/Blip"
strip -x "$app/Contents/MacOS/Blip"
cp Resources/Info.plist "$app/Contents/Info.plist"

swiftc -O -o build/make-icon scripts/make-icon/main.swift Sources/Blip/Pet.swift
build/make-icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$app"
echo "→ $app ($(du -sh "$app" | cut -f1))"

if [[ "${1:-}" == "--install" ]]; then
  pkill -f /Applications/Blip.app/Contents/MacOS/Blip || true
  rm -rf /Applications/Blip.app
  cp -R "$app" /Applications/
  open /Applications/Blip.app
  echo "→ installée dans /Applications"
fi
