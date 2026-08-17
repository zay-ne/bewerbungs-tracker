#!/bin/bash
# Baut Bewerbungen.app aus web/index.html + mac/main.swift.
# Aufruf: ./build-app.sh   (danach die App per Doppelklick starten)

set -euo pipefail
cd "$(dirname "$0")"

APP="Bewerbungen.app"
BUILD=".build"
rm -rf "$BUILD" "$APP"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "› Icon zeichnen"
xcrun swiftc -O mac/icon.swift -o "$BUILD/makeicon"
"$BUILD/makeicon" "$BUILD/Bewerbungen.iconset" web >/dev/null
iconutil -c icns "$BUILD/Bewerbungen.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

echo "› App übersetzen"
xcrun swiftc -O mac/main.swift -o "$APP/Contents/MacOS/Bewerbungen"

echo "› Oberfläche einpacken"
cp web/index.html "$APP/Contents/Resources/index.html"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Bewerbungen</string>
  <key>CFBundleDisplayName</key><string>Bewerbungen</string>
  <key>CFBundleExecutable</key><string>Bewerbungen</string>
  <key>CFBundleIdentifier</key><string>de.schedi.bewerbungen</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "› Signieren (ad-hoc)"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (Signieren übersprungen – App läuft trotzdem)"

rm -rf "$BUILD"
echo
echo "Fertig: $(pwd)/$APP"
echo "Daten liegen in ~/Library/Application Support/Bewerbungen/bewerbungen.json"
