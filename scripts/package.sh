#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

minimum=$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' Resources/Info.plist)
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
binaries=()
for unico_arch in arm64 x86_64; do
    build_dir="$PWD/.build-universal/$unico_arch"
    triple="$unico_arch-apple-macosx$minimum"
    swift build -c release --triple "$triple" --scratch-path "$build_dir"
    bin_dir=$(swift build -c release --triple "$triple" --scratch-path "$build_dir" --show-bin-path)
    binaries+=("$bin_dir/Unico")
done

app="$PWD/dist/Unico.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
xcrun lipo -create "${binaries[@]}" -output "$PWD/.build-universal/Unico-universal"
xcrun lipo "$PWD/.build-universal/Unico-universal" -verify_arch arm64 x86_64
# Replace the executable inode instead of modifying code mapped by a running app.
cp "$PWD/.build-universal/Unico-universal" "$app/Contents/MacOS/Unico.new"
mv -f "$app/Contents/MacOS/Unico.new" "$app/Contents/MacOS/Unico"
chmod +x "$app/Contents/MacOS/Unico"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/icon.swift "$PWD/dist"
iconutil -c icns "$PWD/dist/Unico.iconset" -o "$app/Contents/Resources/Unico.icns"
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
touch "$app"
xcrun vtool -show-build "$app/Contents/MacOS/Unico"
zip="$PWD/dist/Unico-v${version}-macOS-universal.zip"
dmg="$PWD/dist/Unico-v${version}-macOS-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
# Keep the unversioned name for local scripts that used the original artifact.
cp "$zip" "$PWD/dist/Unico-macOS.zip"
dmg_stage=$(mktemp -d "${TMPDIR:-/tmp}/unico-dmg.XXXXXX")
trap 'rm -R "$dmg_stage"' EXIT
cp -R "$app" "$dmg_stage/Unico.app"
ln -s /Applications "$dmg_stage/Applications"
hdiutil create -volname "Unico" -srcfolder "$dmg_stage" -ov -format UDZO "$dmg" >/dev/null
(cd "$PWD/dist" && shasum -a 256 "$(basename "$dmg")" "$(basename "$zip")") > "$PWD/dist/SHA256SUMS.txt"
echo "Built universal macOS $minimum+ app: $app"
echo "Created installer: $dmg"
