#!/bin/bash
# release.sh — helper to cut a new tq release
#
# Usage: ./release.sh 0.2.1
#
# This script:
#   1. Tags the release in the local repo
#   2. Pushes the tag to origin
#   3. Prints the SHA256 for the Homebrew formula

set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 0.2.1"
    exit 1
fi

TAG="v${VERSION}"

# Get the remote URL to determine the GitHub repo
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [ -z "$REMOTE_URL" ]; then
    echo "Error: no git remote 'origin' found"
    exit 1
fi

# Extract username/repo from the URL
REPO=$(echo "$REMOTE_URL" | sed -E 's|.*[:/]([^/]+/[^/]+)\.git$|\1|')
echo "→ Repository: $REPO"
echo "→ Tag:        $TAG"

# Ensure we're on a clean main
BRANCH=$(git branch --show-current)
if [ "$BRANCH" != "main" ]; then
    echo "Error: not on main branch (currently on $BRANCH)"
    exit 1
fi

if ! git diff-index --quiet HEAD --; then
    echo "Error: working tree is dirty. Commit or stash changes first."
    exit 1
fi

# Tag and push
echo "→ Tagging $TAG..."
git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"

# Compute SHA256 from the GitHub archive
ARCHIVE_URL="https://github.com/${REPO}/archive/refs/tags/${TAG}.tar.gz"
echo "→ Computing SHA256 from $ARCHIVE_URL ..."
SHA256=$(curl -sL "$ARCHIVE_URL" | shasum -a 256 | awk '{print $1}')

echo ""
echo "============================================"
echo "  Release $TAG prepared"
echo "============================================"
echo ""
echo "Homebrew formula update:"
echo ""
echo "  url     \"$ARCHIVE_URL\""
echo "  sha256  \"$SHA256\""
echo ""
echo "Now update your homebrew-tq tap:"
echo "  cd ~/path/to/homebrew-tq"
echo "  # Edit Formula/tq.rb with the values above"
echo "  git add Formula/tq.rb && git commit -m 'tq $TAG' && git push"
