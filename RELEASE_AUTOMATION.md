# Automated Releases

This is the machine-followable runbook for cutting a release. It pairs with
`scripts/release.sh`, which performs every mechanical step. For the manual,
explanatory version see [RELEASING.md](RELEASING.md).

## Version state

| Field | File / source | Current value |
|-------|---------------|---------------|
| Marketing version | `ResourceMonitor/Info.plist` → `CFBundleShortVersionString` | `1.0.0` |
| Build number | `ResourceMonitor/Info.plist` → `CFBundleVersion` | `1` |
| Latest released tag | GitHub Releases | `v1.0.0` |
| Next planned version | — | `1.0.1` |

Rules the automation enforces:
- Tag is always `vX.Y.Z` and its numeric part **equals** `CFBundleShortVersionString`.
- `CFBundleVersion` (build number) is incremented by 1 on every release.
- The release is published (not draft/prerelease) so `releases/latest` returns it,
  which is what the in-app updater (`UpdateChecker.swift`) reads.

## One-time-per-release input

Only **one** decision is needed: the next semantic version.

- PATCH (`1.0.0` → `1.0.1`): bug fixes only.
- MINOR (`1.0.0` → `1.1.0`): backwards-compatible features.
- MAJOR (`1.0.0` → `2.0.0`): breaking changes.

## Steps

### 1. Author the changelog (manual — it's content)

In `CHANGELOG.md`, move the items under `## [Unreleased]` into a new dated
section for the version being released, e.g.:

```
## [1.0.1] - 2026-07-08
### Fixed
- Bluetooth battery levels now shown via system_profiler.
```

Also update the link references at the bottom of the file.

`scripts/release.sh` reads this section verbatim as the GitHub release notes and
**aborts if the `## [X.Y.Z]` section is missing**, so this step cannot be skipped.

### 2. Run the release script (automated)

```bash
scripts/release.sh 1.0.1
```

The script then, in order:
1. Verifies the tag `v1.0.1` doesn't already exist.
2. Extracts the `## [1.0.1]` notes from `CHANGELOG.md`.
3. Sets `CFBundleShortVersionString = 1.0.1` and increments `CFBundleVersion`.
4. Builds `-configuration Release` into `build/`.
5. Confirms the built app reports `1.0.1`.
6. Zips `ResourceMonitor.app` → `ResourceMonitor-1.0.1.zip` with `ditto`.
7. `git commit -m "Release 1.0.1"`, `git tag v1.0.1`.
8. Pushes `main` and the tag.
9. `gh release create v1.0.1` with the zip asset and changelog notes.
10. Polls `releases/latest` and prints the resulting tag.

### 3. Confirm

The script prints `releases/latest -> "tag_name": "v1.0.1"`. Open an older build
and use **Settings → General → Updates → Check for updates now** — it should
offer the new version.

## Failure handling

The script uses `set -euo pipefail` and stops at the first error, so a partial
run is safe to diagnose and re-run:
- **Tag already exists** → the version was already released; pick the next one.
- **Missing changelog section** → add `## [X.Y.Z]` and re-run.
- **Version mismatch after build** → stale `build/`; delete it and re-run.
- If it failed *after* pushing the tag but *before* `gh release create`, delete
  the tag (`git push --delete origin vX.Y.Z && git tag -d vX.Y.Z`) and re-run,
  or just run `gh release create` manually.

## Prerequisites

- `gh` authenticated (`gh auth status`).
- Clean working tree apart from the intended release changes.
- Xcode command-line tools available (`xcodebuild`, `ditto`, `PlistBuddy`).
