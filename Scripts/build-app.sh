#!/bin/zsh
# Builds dist/SourceSort.app (release, ad-hoc signed).
# For distribution later: set SIGN_IDENTITY="Developer ID Application: …" and notarize the result
# with `xcrun notarytool submit … --wait` and `xcrun stapler staple`. Not done here.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=1.0
BUILD=${BUILD_NUMBER:-1}
SIGN_IDENTITY=${SIGN_IDENTITY:--}
APP=dist/SourceSort.app

swift build -c release --product SourceSort
BIN=$(swift build -c release --show-bin-path)/SourceSort

rm -rf $APP
mkdir -p $APP/Contents/{MacOS,Resources}
cp $BIN $APP/Contents/MacOS/SourceSort

# Icon: draw once, cache in .build.
ICONSET=.build/AppIcon.iconset
if [[ ! -f .build/AppIcon.icns || Scripts/make-icon.swift -nt .build/AppIcon.icns ]]; then
  rm -rf $ICONSET && mkdir -p $ICONSET
  swift Scripts/make-icon.swift .build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s .build/icon-1024.png --out $ICONSET/icon_${s}x${s}.png >/dev/null
    sips -z $((s * 2)) $((s * 2)) .build/icon-1024.png --out $ICONSET/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns $ICONSET -o .build/AppIcon.icns
fi
cp .build/AppIcon.icns $APP/Contents/Resources/AppIcon.icns

cat > $APP/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.sourcesort.app</string>
  <key>CFBundleName</key><string>SourceSort</string>
  <key>CFBundleDisplayName</key><string>SourceSort</string>
  <key>CFBundleExecutable</key><string>SourceSort</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHumanReadableCopyright</key><string>SourceSort processes file metadata locally on your Mac. Nothing is uploaded.</string>
  <key>NSDownloadsFolderUsageDescription</key><string>SourceSort sorts new files in your Downloads folder using the rules you create.</string>
  <key>NSDesktopFolderUsageDescription</key><string>SourceSort moves files to or from your Desktop when a rule asks it to.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>SourceSort moves files into your Documents folder when a rule asks it to.</string>
</dict>
</plist>
EOF

codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" $APP
codesign --verify --strict --verbose=2 $APP
plutil -lint $APP/Contents/Info.plist
echo "Built $APP"
