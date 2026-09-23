#!/bin/zsh
set -u
cd "${0:A:h:h}"

app="${1:-dist/Unico.app}"
failures=0
pass() { print "PASS  $1"; }
warn() { print "WARN  $1"; }
fail() { print "FAIL  $1"; failures=$((failures + 1)); }

[[ -d "$app" ]] || { fail "app bundle not found: $app"; exit 1; }
plutil -lint "$app/Contents/Info.plist" >/dev/null 2>&1 && pass "Info.plist is valid" || fail "Info.plist is invalid"
[[ -x "$app/Contents/MacOS/Unico" ]] && pass "executable exists" || fail "executable missing"
[[ -f "$app/Contents/Resources/Unico.icns" ]] && pass "app icon is bundled" || fail "app icon missing"
if [[ -f "$app/Contents/Resources/PrivacyInfo.xcprivacy" ]] && plutil -lint "$app/Contents/Resources/PrivacyInfo.xcprivacy" >/dev/null 2>&1; then
  pass "privacy manifest is bundled and valid"
else
  fail "privacy manifest missing or invalid"
fi

bundle_id=$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)
category=$(plutil -extract LSApplicationCategoryType raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)
[[ "$bundle_id" == "cc.leowy.unico" ]] && pass "bundle identifier: $bundle_id" || fail "unexpected bundle identifier"
[[ "$category" == "public.app-category.utilities" ]] && pass "App Store category: Utilities" || fail "missing App Store category"
uses_non_exempt_encryption=$(plutil -extract ITSAppUsesNonExemptEncryption raw -o - "$app/Contents/Info.plist" 2>/dev/null || true)
[[ "$uses_non_exempt_encryption" == "false" || "$uses_non_exempt_encryption" == "0" ]] && pass "export-compliance declaration is present" || fail "missing or unexpected export-compliance declaration"

archs=$(lipo -archs "$app/Contents/MacOS/Unico" 2>/dev/null || true)
[[ "$archs" == *arm64* && "$archs" == *x86_64* ]] && pass "universal binary" || fail "universal binary missing an architecture"

signature=$(codesign -dvvv "$app" 2>&1 || true)
if [[ "$signature" == *"Signature=adhoc"* ]]; then
  warn "ad hoc signature; Apple Distribution signing remains required"
elif [[ "$signature" == *"TeamIdentifier="* && "$signature" != *"TeamIdentifier=not set"* ]]; then
  pass "non-ad-hoc signature present"
else
  warn "signature could not be classified"
fi

[[ -f docs/PRIVACY_POLICY.md ]] && pass "privacy policy source exists" || fail "privacy policy source missing"
[[ -f docs/APP_STORE_METADATA.md ]] && pass "App Store metadata checklist exists" || fail "App Store metadata checklist missing"
[[ -f docs/WEB_DEPLOYMENT.md ]] && pass "public support deployment guide exists" || fail "public support deployment guide missing"
exit "$failures"
