#!/usr/bin/env bash
# Local release: test -> pick version -> build -> dmg -> tag -> GitHub release.
#
#   scripts/release.sh                 # auto version from conventional commits, asks before publishing
#   scripts/release.sh --dry-run       # print the version + notes, change nothing
#   scripts/release.sh --no-publish    # test + build + dmg into dist/, no tag/push/release
#   scripts/release.sh --version 0.2.0-beta.1
#   scripts/release.sh --stable        # leave the beta stream (0.1.0-beta.3 -> 0.1.0)
#   scripts/release.sh --yes           # skip the confirmation prompt
#
# Versioning (Conventional Commits since the last v* tag):
#   first release            -> 0.1.0-beta
#   last tag is a beta       -> next beta: 0.1.0-beta -> 0.1.0-beta.1 -> 0.1.0-beta.2 ...
#   last tag is stable       -> feat: minor, fix: patch, breaking (feat!: / BREAKING CHANGE): major
#                               (while 0.x a breaking change bumps minor)
#   only chore/docs/ci/test  -> nothing to release
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0 PUBLISH=1 STABLE=0 ASSUME_YES=0 FORCED_VERSION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-publish) PUBLISH=0 ;;
    --stable) STABLE=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --version) FORCED_VERSION="${2:?--version needs a value}"; shift ;;
    -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "missing tool: $1 ($2)"; }

need git "xcode-select --install"
need swift "install Xcode"
need xcodebuild "install Xcode"
need xcodegen "brew install xcodegen"
[[ $PUBLISH -eq 1 && $DRY_RUN -eq 0 ]] && need gh "brew install gh"

# ---------- preconditions ----------
if [[ $PUBLISH -eq 1 && $DRY_RUN -eq 0 ]]; then
  [[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || die "release from the main branch"
  [[ -z "$(git status --porcelain)" ]] || die "working tree isn't clean; commit or stash first"
  git fetch -q origin main 2>/dev/null || true
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main 2>/dev/null || git rev-parse HEAD)" ]] \
    || die "main differs from origin/main; push or pull first"
fi

# ---------- version ----------
LAST_TAG="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true)"
RANGE="${LAST_TAG:+$LAST_TAG..}HEAD"
SUBJECTS="$(git log "$RANGE" --format=%s)"
[[ -n "$SUBJECTS" ]] || die "no commits since ${LAST_TAG:-the start}"

bump_kind() {
  if git log "$RANGE" --format=%B | grep -q '^BREAKING CHANGE' || grep -qE '^[a-z]+(\([^)]*\))?!:' <<<"$SUBJECTS"; then echo major
  elif grep -qE '^feat(\([^)]*\))?:' <<<"$SUBJECTS"; then echo minor
  elif grep -qE '^fix(\([^)]*\))?:' <<<"$SUBJECTS"; then echo patch
  else echo none; fi
}

next_version() {
  [[ -n "$LAST_TAG" ]] || { echo "0.1.0-beta"; return; }
  local cur="${LAST_TAG#v}" base pre major minor patch
  base="${cur%%-*}"; pre=""; [[ "$cur" == *-* ]] && pre="${cur#*-}"
  IFS=. read -r major minor patch <<<"$base"

  if [[ -n "$pre" && $STABLE -eq 1 ]]; then echo "$base"; return; fi
  if [[ -n "$pre" ]]; then
    # beta stream: beta -> beta.1 -> beta.2
    local n="${pre#beta}"; n="${n#.}"
    echo "$base-beta.$(( ${n:-0} + 1 ))"; return
  fi

  case "$(bump_kind)" in
    major) if [[ $major -eq 0 ]]; then echo "0.$((minor + 1)).0"; else echo "$((major + 1)).0.0"; fi ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
    none) echo "" ;;
  esac
}

if [[ -n "$FORCED_VERSION" ]]; then VERSION="${FORCED_VERSION#v}"; else VERSION="$(next_version)"; fi
[[ -n "$VERSION" ]] || die "only chore/docs/ci/test commits since $LAST_TAG; nothing to release (use --version to force)"
TAG="v$VERSION"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists"
NUMERIC="${VERSION%%-*}"          # CFBundleShortVersionString must be numeric
BUILD_NUMBER="$(git rev-list --count HEAD)"

# ---------- release notes ----------
section() { # title, regex
  local lines; lines="$(grep -E "$2" <<<"$SUBJECTS" | sed -E 's/^[a-z]+(\(([^)]*)\))?!?: /\2@@/; s/^@@//; s/^([^@]+)@@/**\1:** /; s/^/- /' || true)"
  [[ -n "$lines" ]] && printf '### %s\n%s\n\n' "$1" "$lines"
  return 0
}
NOTES="$(
  section "Breaking changes" '^[a-z]+(\([^)]*\))?!:'
  section "Features" '^feat(\([^)]*\))?:'
  section "Bug fixes" '^fix(\([^)]*\))?:'
  section "Performance" '^perf(\([^)]*\))?:'
  section "Refactoring" '^refactor(\([^)]*\))?:'
)"
[[ -n "$NOTES" ]] || NOTES="Maintenance release."

echo "last tag : ${LAST_TAG:-none}"
echo "version  : $VERSION  (tag $TAG, build $BUILD_NUMBER)"
echo
echo "$NOTES"
[[ $DRY_RUN -eq 1 ]] && { echo "(dry run: nothing changed)"; exit 0; }

# ---------- test + build + package ----------
echo "==> swift test"
swift test 2>&1 | tail -3

echo "==> xcodegen + xcodebuild (Release)"
xcodegen generate >/dev/null
rm -rf build
xcodebuild -project DropCat.xcodeproj -scheme DropCat -configuration Release \
  -destination 'platform=macOS' -derivedDataPath build \
  MARKETING_VERSION="$NUMERIC" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

APP="build/Build/Products/Release/DropCat.app"
[[ -d "$APP" ]] || die "build failed: $APP not found"

mkdir -p dist
DMG="dist/DropCat-$TAG.dmg"
rm -f "$DMG"

# Disk image with the usual drag-to-Applications layout. This is the only release asset;
# GitHub adds "Source code (zip / tar.gz)" to every release on its own.
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "DropCat $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null 2>&1
rm -rf "$STAGE"
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "==> built $DMG ($(du -h "$DMG" | cut -f1))"

RELEASE_NOTES="$NOTES

### Install
1. Download **DropCat-$TAG.dmg** below and open it.
2. Drag **DropCat** into **Applications**.
3. First launch: right-click the app and choose **Open** (the build is not notarized).

\`SHA-256: $SHA\`"

[[ $PUBLISH -eq 1 ]] || { echo "(--no-publish: stopping before tag/push/release)"; exit 0; }

# ---------- tag + publish ----------
if [[ $ASSUME_YES -eq 0 ]]; then
  read -r -p "Publish $TAG to GitHub now? [y/N] " ans
  [[ "$ans" == [yY]* ]] || { echo "aborted; build left in dist/"; exit 0; }
fi

git tag -a "$TAG" -m "DropCat $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$DMG" --title "DropCat $VERSION" --notes "$RELEASE_NOTES" --latest
echo "==> released $TAG"
