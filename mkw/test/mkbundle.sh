#!/bin/sh
# mkbundle.sh <bundle dir> <bundle id> <true|false> <host binary>: a minimal app bundle around a host binary, so that a bench run of that host is an app to macOS
# (Game Mode applies to app bundles of a games category only; true or false is the bundle's LSSupportsGameMode). mkw/test/host_open.py starts
# <bundle>/Contents/MacOS/dmhost with the bench's settings in the environment. The bundle is made anew each time: macOS's Game Mode daemon keeps its verdict on a
# bundle until the bundle folder's modification date changes (mkw/KNOWLEDGE.md, section 0), so a key changed in place is not looked at again.
set -e
A=$1; ID=$2; GM=$3; H=$4
rm -rf "$A"; mkdir -p "$A/Contents/MacOS"
cp -c "$H" "$A/Contents/MacOS/dmhost" 2>/dev/null || cp "$H" "$A/Contents/MacOS/dmhost"
cat > "$A/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$(basename "$A" .app)</string>
  <key>CFBundleDisplayName</key><string>$(basename "$A" .app)</string>
  <key>CFBundleExecutable</key><string>dmhost</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.racing-games</string>
  <key>LSMinimumSystemVersion</key><string>26.6</string>
  <key>LSSupportsGameMode</key><$GM/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
printf 'APPL????' > "$A/Contents/PkgInfo"
codesign --force --sign - "$A" >/dev/null 2>&1
codesign -dv "$A" 2>&1 | grep -E "Identifier|Signature" | tr '\n' ' '; echo
plutil -p "$A/Contents/Info.plist" | grep -E "GameMode|Identifier|Category"
