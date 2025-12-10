#!/bin/bash

set -euo pipefail

# Update Vikunja Flatpak to a new version
# Usage: ./update-version.sh <version>
# Example: ./update-version.sh 0.24.4

VERSION="${1:-}"

# Validate version is provided
if [ -z "$VERSION" ]; then
    echo "Error: Version number required"
    echo "Usage: $0 <version>"
    echo "Example: $0 0.24.4 or $0 v1.0.0-rc1"
    exit 1
fi

# Strip 'v' prefix if present
VERSION="${VERSION#v}"

# Validate version format (semver with optional pre-release: X.Y.Z or X.Y.Z-rc1)
if ! echo "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.]+)?$'; then
    echo "Error: Invalid version format. Expected X.Y.Z or X.Y.Z-rc1 (e.g., 0.24.4 or 1.0.0-rc1)"
    exit 1
fi

echo "Updating Vikunja to version $VERSION..."

# Construct download URL based on version
# v1.x and higher use: /desktop/v{version}/Vikunja Desktop-unstable.tar.gz
# v0.x uses: /desktop/{version}/Vikunja Desktop-v{version}.tar.gz (but we're not supporting this anymore)
if [[ "$VERSION" =~ ^1\. ]]; then
    # v1.x versions: directory has 'v' prefix, filename is 'unstable'
    DOWNLOAD_URL="https://dl.vikunja.io/desktop/v${VERSION}/Vikunja%20Desktop-unstable.tar.gz"
else
    echo "Error: Only v1.x versions are supported"
    exit 1
fi

TEMP_FILE=$(mktemp)

# Download the release tarball
echo "Downloading $DOWNLOAD_URL..."
if ! curl -L -f -o "$TEMP_FILE" "$DOWNLOAD_URL"; then
    echo "Error: Failed to download release. Version $VERSION may not exist."
    rm -f "$TEMP_FILE"
    exit 1
fi

# Calculate SHA256 hash
echo "Calculating SHA256 hash..."
SHA256=$(sha256sum "$TEMP_FILE" | cut -d' ' -f1)
echo "SHA256: $SHA256"

# Clean up the downloaded file
rm -f "$TEMP_FILE"

# Update io.vikunja.Vikunja.yml
MANIFEST_FILE="io.vikunja.Vikunja.yml"
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "Error: $MANIFEST_FILE not found"
    exit 1
fi

echo "Updating $MANIFEST_FILE..."
# Update the URL line (matches both old and new URL formats)
# Note: sed -i behaves differently on macOS vs Linux, so we use a temp file approach
sed "s|url: https://dl.vikunja.io/desktop/.*\.tar\.gz|url: $DOWNLOAD_URL|" "$MANIFEST_FILE" > "$MANIFEST_FILE.tmp"
mv "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"
# Update the SHA256 line
sed "s/sha256: .*/sha256: $SHA256/" "$MANIFEST_FILE" > "$MANIFEST_FILE.tmp"
mv "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"

# Update io.vikunja.Vikunja.appdata.xml
APPDATA_FILE="io.vikunja.Vikunja.appdata.xml"
if [ ! -f "$APPDATA_FILE" ]; then
    echo "Error: $APPDATA_FILE not found"
    exit 1
fi

echo "Updating $APPDATA_FILE..."
# Fetch the actual release date from GitHub
echo "Fetching release date from GitHub..."
RELEASE_DATE=$(curl -sL "https://api.github.com/repos/go-vikunja/vikunja/releases/tags/v${VERSION}" | \
    grep '"published_at"' | \
    head -1 | \
    sed 's/.*"published_at": "\([^T]*\).*/\1/')

if [ -z "$RELEASE_DATE" ]; then
    echo "Warning: Could not fetch release date from GitHub, using current date"
    RELEASE_DATE=$(date +%Y-%m-%d)
else
    echo "Release date: $RELEASE_DATE"
fi

# Insert new release entry after the <releases> opening tag
# Use awk for better cross-platform compatibility
awk -v version="$VERSION" -v date="$RELEASE_DATE" '
/<releases>/ {
    print
    print "\t\t<release version=\"" version "\" date=\"" date "\" />"
    next
}
{ print }
' "$APPDATA_FILE" > "$APPDATA_FILE.tmp"
mv "$APPDATA_FILE.tmp" "$APPDATA_FILE"

echo "Successfully updated to version $VERSION"
