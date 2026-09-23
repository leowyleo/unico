#!/bin/zsh
set -u
cd "${0:A:h:h}"

app="${1:-dist/Unico.app}"
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist" 2>/dev/null || print unknown)
build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist" 2>/dev/null || print unknown)
pkg="${2:-dist/Unico-v${version}-${build}-mac-app-store.pkg}"
failures=0
pass() { print "PASS  $1"; }
fail() { print "FAIL  $1"; failures=$((failures + 1)); }

[[ -d "$app" ]] || { fail "app bundle not found: $app"; exit 1; }
[[ -f "$pkg" ]] || { fail "submission package not found: $pkg"; exit 1; }

./scripts/check-release-readiness.sh "$app" || failures=$((failures + 1))

store_build=$(plutil -extract UnicoAppStoreBuild raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)
[[ "$store_build" == "true" || "$store_build" == "1" ]] && pass "App Store build mode is enabled" || fail "UnicoAppStoreBuild is not enabled"

profile="$app/Contents/embedded.provisionprofile"
profile_plist=""
entitlements=$(mktemp "${TMPDIR:-/tmp}/unico-entitlements.XXXXXX")
trap 'rm -f "$profile_plist" "$entitlements"' EXIT
if [[ -f "$profile" ]]; then
  profile_plist=$(mktemp "${TMPDIR:-/tmp}/unico-profile-check.XXXXXX")
  if security cms -D -i "$profile" > "$profile_plist" 2>/dev/null; then
    profile_id=$(
      /usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$profile_plist" 2>/dev/null ||
        /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$profile_plist" 2>/dev/null || true
    )
    [[ "$profile_id" == *.cc.leowy.unico ]] && pass "embedded profile matches cc.leowy.unico" || fail "embedded profile does not match cc.leowy.unico"
  else
    fail "embedded provisioning profile is unreadable"
  fi
else
  fail "embedded provisioning profile is missing"
fi

signature=$(codesign -dvvv "$app" 2>&1 || true)
if [[ "$signature" == *"Signature=adhoc"* || "$signature" == *"TeamIdentifier=not set"* ]]; then
  fail "app is not signed with an Apple distribution team"
elif [[ "$signature" == *"Authority=Apple Distribution:"* || "$signature" == *"Authority=3rd Party Mac Developer Application:"* || "$signature" == *"Authority=Mac App Distribution:"* ]]; then
  pass "app has an App Store distribution signature"
else
  fail "app signing authority is not an App Store distribution identity"
fi

if codesign -d --entitlements :- "$app" > "$entitlements" 2>/dev/null && \
   [[ $(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$entitlements" 2>/dev/null || true) == "true" ]]; then
  pass "App Sandbox entitlement is present"
else
  fail "App Sandbox entitlement is missing"
fi

pkgutil --check-signature "$pkg" >/dev/null 2>&1 && pass "installer package has a valid signature" || fail "installer package signature is invalid"
exit "$failures"
