#!/bin/sh
# Release gate: тег vX.Y.Z должен совпадать с версией SDK и иметь запись в CHANGELOG.
set -eu
VERSION="${1:?usage: verify-release.sh <version, e.g. 0.1.0>}"

if ! grep -q "public static let version = \"$VERSION\"" Sources/BoomstreamAPI/Version.swift; then
  echo "verify-release: FAIL — Version.swift does not declare version $VERSION" >&2
  exit 1
fi
if ! grep -q "^## \[$VERSION\]" CHANGELOG.md; then
  echo "verify-release: FAIL — CHANGELOG.md has no entry for $VERSION" >&2
  exit 1
fi
echo "verify-release: OK ($VERSION)"
