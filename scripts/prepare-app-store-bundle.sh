#!/bin/zsh
set -euo pipefail

# Build the Mac App Store submission package. The credentials remain in the
# local Keychain and provisioning-profile cache; do not paste them into chat.
#
# Required environment variables:
# - APP_STORE_APPLICATION_IDENTITY: an App Store application-signing identity.
# - MAC_APP_STORE_INSTALLER_IDENTITY: normally "3rd Party Mac Developer Installer: …".
# - APP_STORE_PROVISIONING_PROFILE: a Mac App Store Connect .provisionprofile
#   for cc.leowy.unico.
cd "${0:A:h:h}"

: "${APP_STORE_APPLICATION_IDENTITY:?Set the App Store application signing identity first.}"
: "${MAC_APP_STORE_INSTALLER_IDENTITY:?Set the Mac Installer Distribution signing identity first.}"
: "${APP_STORE_PROVISIONING_PROFILE:?Set the path to the App Store provisioning profile first.}"

case "$APP_STORE_APPLICATION_IDENTITY" in
  "Apple Distribution: "*|"3rd Party Mac Developer Application: "*|"Mac App Distribution: "*) ;;
  *) print -u2 "Use an App Store application signing identity, not a development or Developer ID identity."; exit 2 ;;
esac
case "$MAC_APP_STORE_INSTALLER_IDENTITY" in
  "3rd Party Mac Developer Installer: "*|"Mac Installer Distribution: "*) ;;
  *) print -u2 "Use a Mac Installer Distribution identity, not a Developer ID Installer identity."; exit 2 ;;
esac

if [[ ! -f "$APP_STORE_PROVISIONING_PROFILE" ]]; then
    print -u2 "Provisioning profile was not found: $APP_STORE_PROVISIONING_PROFILE"
    exit 2
fi

contains_identity() {
    local identity="$1"
    local policy="$2"
    if [[ "$policy" == "codesigning" ]]; then
        security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$identity\""
    else
        security find-identity -v 2>/dev/null | grep -Fq "\"$identity\""
    fi
}

if ! contains_identity "$APP_STORE_APPLICATION_IDENTITY" codesigning; then
    print -u2 "App Store application signing identity is not available in this Keychain: $APP_STORE_APPLICATION_IDENTITY"
    exit 2
fi
if ! contains_identity "$MAC_APP_STORE_INSTALLER_IDENTITY" installer; then
    print -u2 "Mac Installer Distribution identity is not available in this Keychain: $MAC_APP_STORE_INSTALLER_IDENTITY"
    exit 2
fi

profile_plist=$(mktemp "${TMPDIR:-/tmp}/unico-profile.XXXXXX")
trap 'rm -f "$profile_plist"' EXIT
security cms -D -i "$APP_STORE_PROVISIONING_PROFILE" > "$profile_plist"
profile_bundle_id=$(
  /usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$profile_plist" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$profile_plist"
)
if [[ "$profile_bundle_id" != *.cc.leowy.unico ]]; then
    print -u2 "Provisioning profile does not match cc.leowy.unico: $profile_bundle_id"
    exit 2
fi

zsh ./scripts/package.sh
app="$PWD/dist/Unico.app"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")
pkg="$PWD/dist/Unico-v${version}-${build}-mac-app-store.pkg"

if [[ -e "$pkg" ]]; then
    print -u2 "Refusing to overwrite an existing submission package: $pkg"
    print -u2 "Increment CFBundleVersion for a new upload, then rerun this script."
    exit 2
fi

/usr/libexec/PlistBuddy -c 'Add UnicoAppStoreBuild bool true' "$app/Contents/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c 'Set UnicoAppStoreBuild true' "$app/Contents/Info.plist"
cp Resources/PrivacyInfo.xcprivacy "$app/Contents/Resources/PrivacyInfo.xcprivacy"
cp "$APP_STORE_PROVISIONING_PROFILE" "$app/Contents/embedded.provisionprofile"

# Apple rejects quarantine and Finder metadata inside Mac App Store packages
# (notably on downloaded provisioning profiles). Strip all extended attributes
# from the staged app before signing so they cannot be copied into the pkg.
xattr -rc "$app" 2>/dev/null || true

# App Store Connect re-signs submitted apps. A secure timestamp is required for
# Developer ID notarization, not for this App Store submission package.
codesign --force --options runtime --timestamp=none \
  --entitlements Resources/Unico-AppStore.entitlements \
  --sign "$APP_STORE_APPLICATION_IDENTITY" "$app"
codesign --verify --deep --strict "$app"
signature_details=$(codesign -dvvv "$app" 2>&1 || true)
if [[ "$signature_details" != *"Authority=$APP_STORE_APPLICATION_IDENTITY"* ]]; then
  print -u2 "The app signature does not match the requested App Store application identity."
  exit 2
fi
productbuild --sign "$MAC_APP_STORE_INSTALLER_IDENTITY" \
  --component "$app" /Applications "$pkg"
pkgutil --check-signature "$pkg"
./scripts/check-app-store-submission.sh "$app" "$pkg"
print "Prepared Mac App Store submission package: $pkg"
