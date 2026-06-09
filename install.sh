#!/bin/sh
# Builds UngreasedHinge.app and installs it into /Applications
# (falls back to ~/Applications if /Applications is not writable).
#
# The app is a background utility with no UI: opening it starts the hinge
# creak, opening it again stops it. The bundle's main "executable" is a
# launcher script that spawns the real binary detached and exits immediately —
# otherwise Launch Services would refuse to relaunch a running app and the
# open-again-to-stop toggle would never fire.
set -eu

cd "$(dirname "$0")"
swift build -c release

APP_DIR="/Applications"
[ -w "$APP_DIR" ] || APP_DIR="$HOME/Applications"
mkdir -p "$APP_DIR"
APP="$APP_DIR/UngreasedHinge.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BUILD_DIR="$(swift build -c release --show-bin-path)"
cp "$BUILD_DIR/UngreasedHinge" "$APP/Contents/MacOS/UngreasedHingeBin"
cp -R "$BUILD_DIR/ungreased-hinge_UngreasedHinge.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/MacOS/UngreasedHinge" <<'LAUNCHER'
#!/bin/sh
DIR="$(cd "$(dirname "$0")" && pwd)"
nohup "$DIR/UngreasedHingeBin" >/dev/null 2>&1 &
LAUNCHER
chmod +x "$APP/Contents/MacOS/UngreasedHinge"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>UngreasedHinge</string>
	<key>CFBundleIdentifier</key>
	<string>com.semihsmg.ungreased-hinge</string>
	<key>CFBundleName</key>
	<string>UngreasedHinge</string>
	<key>CFBundleDisplayName</key>
	<string>Ungreased Hinge</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP/Contents/MacOS/UngreasedHingeBin"
codesign --force --sign - "$APP"

echo "installed: $APP"
