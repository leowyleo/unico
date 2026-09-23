# Validation — v1.1.3

Verified locally on Apple Silicon / macOS 26.5.1. This is a community preview, not a guarantee that every file is safe to remove.

## Automated checks

31 XCTest cases passed on 2026-09-10. Coverage includes exact-content grouping, keep selection, cancellation, unreadable locations, links/hard links, default exclusions, explicit-folder confirmation, scope isolation, whole-disk ignoring manual confirmation, cleanup revalidation, Trash failure, generated-file Trash/recovery, and the App Store build flag that removes whole-disk scanning.

Reproduce with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path .build-tests
```

Tests generate their own files under the test user's home directory and remove their fixtures afterwards. A few tests exercise real Trash and restore the sample files.

## Actual app checks

- A generated project fixture with two PNG copies and hidden JSON copies is accepted after the explicit scope warning; Cancel leaves the scan unstarted.
- Results show the expected two duplicate groups. Thumbnail selection changes the large preview without changing cleanup choices.
- Changing the keeper leaves one protected keeper per group.
- The native title-bar language menu switches English / Simplified Chinese without losing scan or selection state.
- Normal and minimum-window layouts retain visible controls without overlapping the preview.
- Cleanup has a separate warning about app/project/system files. No personal files were cleaned during QA.

Screenshots in `promo/screenshots/` are from the app running on generated fixtures, not UI mockups.

## Package checks

- Both arm64 and x86_64 executable slices target macOS 12.0.
- Ad-hoc code-signature verification passes.
- ZIP contents match the packaged app; release SHA-256 is supplied separately.
- macOS 12/13 and Intel hardware runtime checks are still outstanding.
- No Developer ID signature or Apple notarization. Distribution must disclose this limitation.

## Deliberate limits

Unico does not infer whether a second path is required by another app. Explicit folder confirmation may include sensitive application or system files; users must judge whether those copies are disposable. Unico never elevates privileges, empties Trash, or falls back to permanent deletion. Revalidation reduces risk but is not a substitute for backups.
