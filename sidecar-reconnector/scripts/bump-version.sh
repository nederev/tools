#!/bin/sh
set -eu

plist="app/Info.plist"
version=""
build=""
increment_build=1

usage() {
  cat <<'EOF'
Usage:
  scripts/bump-version.sh [--version <short-version>] [--build <build-number>] [--no-build-increment]

Examples:
  make bump-build
  make bump-version VERSION=0.2
  make bump-version VERSION=0.2 BUILD=7
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      version="${2:-}"
      shift 2
      ;;
    --build)
      build="${2:-}"
      increment_build=0
      shift 2
      ;;
    --no-build-increment)
      increment_build=0
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ ! -f "$plist" ]; then
  echo "missing $plist; run from sidecar-reconnector/" >&2
  exit 1
fi

current_version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$plist")
current_build=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$plist")

if [ -z "$version" ]; then
  version="$current_version"
fi

case "$version" in
  *[!0-9.]*|"")
    echo "invalid version: $version" >&2
    exit 2
    ;;
esac

if [ -z "$build" ]; then
  case "$current_build" in
    *[!0-9]*|"")
      echo "current CFBundleVersion is not numeric: $current_build" >&2
      exit 2
      ;;
  esac
  if [ "$increment_build" -eq 1 ]; then
    build=$((current_build + 1))
  else
    build="$current_build"
  fi
fi

case "$build" in
  *[!0-9]*|"")
    echo "invalid build number: $build" >&2
    exit 2
    ;;
esac

/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $version" "$plist"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $build" "$plist"
perl -0pi -e 's/\n\t/\n  /g' "$plist"

echo "Sidecar Reconnector version: $current_version ($current_build) -> $version ($build)"
