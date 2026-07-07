#!/usr/bin/env bash
#
# Automated release for ResourceMonitor.
#
#   scripts/release.sh X.Y.Z
#
# Prerequisites:
#   - CHANGELOG.md already has a "## [X.Y.Z] - YYYY-MM-DD" section (the script
#     uses it as the release notes).
#   - Working tree is clean apart from the changes you intend to release.
#   - `gh` is authenticated.
#
# The script bumps the version, builds Release, zips the app, commits, tags,
# pushes, and publishes the GitHub release with the changelog notes attached.

set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: scripts/release.sh X.Y.Z" >&2
  exit 1
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must be MAJOR.MINOR.PATCH (e.g. 1.0.1)" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PLIST="ResourceMonitor/Info.plist"
TAG="v$VERSION"

# Refuse to re-release an existing tag.
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "error: tag $TAG already exists" >&2
  exit 1
fi

# Require the changelog section so releases are always documented.
NOTES="$(awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" {f=1; next}
  f && /^## \[/ {f=0}
  f {print}
' CHANGELOG.md | sed -e 's/^[[:space:]]*//' -e '/^$/d')"
if [[ -z "$NOTES" ]]; then
  echo "error: no '## [$VERSION]' section found in CHANGELOG.md" >&2
  echo "       add the changelog entry before releasing." >&2
  exit 1
fi

echo "==> Bumping version to $VERSION"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
BUILD_NUM="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD_NUM + 1))" "$PLIST"

echo "==> Building Release"
xcodebuild -project ResourceMonitor.xcodeproj -scheme ResourceMonitor \
  -configuration Release -derivedDataPath build clean build >/dev/null

APP="build/Build/Products/Release/ResourceMonitor.app"
GOT="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")"
if [[ "$GOT" != "$VERSION" ]]; then
  echo "error: built app reports $GOT, expected $VERSION" >&2
  exit 1
fi

echo "==> Packaging ResourceMonitor-$VERSION.zip"
ZIP="ResourceMonitor-$VERSION.zip"
( cd "$(dirname "$APP")" && ditto -c -k --sequesterRsrc --keepParent "ResourceMonitor.app" "$ZIP" )
ASSET="$(dirname "$APP")/$ZIP"

echo "==> Committing and tagging"
git add "$PLIST" CHANGELOG.md
git commit -m "Release $VERSION"
git tag "$TAG"

echo "==> Pushing"
git push origin main
git push origin "$TAG"

echo "==> Publishing GitHub release"
gh release create "$TAG" "$ASSET" \
  --title "ResourceMonitor $VERSION" \
  --notes "$NOTES"

echo "==> Verifying updater endpoint"
sleep 2
LATEST="$(curl -s "https://api.github.com/repos/tuei2/ResourceMonitor/releases/latest" | grep '"tag_name"' | head -1)"
echo "    releases/latest -> $LATEST"

echo "Done. Released $VERSION."
