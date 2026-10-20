#!/usr/bin/env bash
# Attach the freshly built unsigned .ipas to the rolling web-build release.
set -euo pipefail
TAG="web-build"

if ! gh release view "$TAG" -R "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  gh release create "$TAG" -R "$GITHUB_REPOSITORY" \
    --title "Unsigned IPAs built from incoming .debs" \
    --notes "Rolling release of unsigned .ipa files built by the 'Build unsigned IPA' workflow from .deb packages uploaded to incoming/. No certificates are included — sideload with SideStore / AltStore / Sideloadly, which apply your own Apple ID signature at install time."
fi

gh release upload "$TAG" -R "$GITHUB_REPOSITORY" out/*.ipa --clobber
echo "Published to release: $TAG"
