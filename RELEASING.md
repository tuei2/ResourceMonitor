# Releasing ResourceMonitor

Step-by-step guide for shipping a new version. Follow every step in order — the
in-app updater depends on the version number and the Git tag matching exactly.

## How the auto-updater works

On launch (max once per 24h) and via **Settings → General → Updates → Check for
updates now**, the app calls:

```
https://api.github.com/repos/tuei2/ResourceMonitor/releases/latest
```

It reads the release's `tag_name`, strips a leading `v`, and compares it to the
app's `CFBundleShortVersionString` (see `UpdateChecker.swift`). If the tag is a
higher version, the user is offered the release's `html_url` to download.

**Consequences:**
- The Git tag **must** be `vX.Y.Z` and its numeric part **must** match the
  `CFBundleShortVersionString` you built with.
- The release must **not** be a draft or pre-release, or `releases/latest` won't
  return it.
- Version numbers follow [SemVer](https://semver.org): `MAJOR.MINOR.PATCH`.

## Release checklist

### 1. Pick the new version

Decide `X.Y.Z` per SemVer (breaking = MAJOR, feature = MINOR, fix = PATCH).
This guide uses `1.1.0` as the example.

### 2. Update the changelog

In `CHANGELOG.md`:
- Move items from `## [Unreleased]` into a new `## [1.1.0] - YYYY-MM-DD` section
  (use today's date).
- Group under `Added` / `Changed` / `Fixed` / `Removed`.
- Add the two link references at the bottom:
  ```
  [Unreleased]: https://github.com/tuei2/ResourceMonitor/compare/v1.1.0...HEAD
  [1.1.0]: https://github.com/tuei2/ResourceMonitor/releases/tag/v1.1.0
  ```
  and update the previous `[Unreleased]` compare link's base to `v1.1.0`.

### 3. Bump the version

In `ResourceMonitor/Info.plist`:
- `CFBundleShortVersionString` → `1.1.0` (the marketing version the updater compares).
- `CFBundleVersion` → increment the integer build number (e.g. `1` → `2`).

### 4. Build a Release archive

```bash
cd /path/to/ResourceMonitor
xcodebuild -project ResourceMonitor.xcodeproj \
  -scheme ResourceMonitor -configuration Release \
  -derivedDataPath build clean build
```

The app is produced at:
`build/Build/Products/Release/ResourceMonitor.app`

Smoke-test it: launch it, open Settings, confirm the version shows `1.1.0`.

### 5. Zip the app for distribution

```bash
cd build/Build/Products/Release
ditto -c -k --sequesterRsrc --keepParent ResourceMonitor.app ResourceMonitor-1.1.0.zip
cd -
```

(`ditto` preserves the app bundle and code signature; don't use Finder-zip in scripts.)

### 6. Commit and tag

```bash
git add CHANGELOG.md ResourceMonitor/Info.plist
git commit -m "Release 1.1.0"
git tag v1.1.0
git push origin main
git push origin v1.1.0
```

### 7. Publish the GitHub release

Use the changelog section as the release notes. The tag must already be pushed.

```bash
gh release create v1.1.0 \
  build/Build/Products/Release/ResourceMonitor-1.1.0.zip \
  --title "ResourceMonitor 1.1.0" \
  --notes-file <(sed -n '/## \[1.1.0\]/,/## \[/p' CHANGELOG.md | sed '$d')
```

Or, to write notes by hand:

```bash
gh release create v1.1.0 build/Build/Products/Release/ResourceMonitor-1.1.0.zip \
  --title "ResourceMonitor 1.1.0" --notes "See CHANGELOG.md"
```

Do **not** pass `--draft` or `--prerelease` — the updater only sees the latest
published, non-prerelease release.

### 8. Verify the updater sees it

```bash
curl -s https://api.github.com/repos/tuei2/ResourceMonitor/releases/latest \
  | grep '"tag_name"'
```

Should print `"tag_name": "v1.1.0"`. Then open an older build of the app and use
**Check for updates now** — it should offer 1.1.0.

## Quick reference

| Item | Where | Example |
|------|-------|---------|
| Marketing version | `Info.plist` → `CFBundleShortVersionString` | `1.1.0` |
| Build number | `Info.plist` → `CFBundleVersion` | `2` |
| Git tag | `git tag` | `v1.1.0` |
| Release title | `gh release create --title` | `ResourceMonitor 1.1.0` |
| Changelog entry | `CHANGELOG.md` | `## [1.1.0] - YYYY-MM-DD` |

The tag's numeric part, the `CFBundleShortVersionString`, and the changelog
version must all be the same three numbers.
