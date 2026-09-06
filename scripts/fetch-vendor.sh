#!/usr/bin/env bash
# fetch-vendor.sh --- Populate docs/content/assets/vendor/ with all third-party
# assets needed by the reveal.js talks so that the built site works fully
# offline.  Idempotent: skips downloads whose output already exists.  Delete
# docs/content/assets/vendor/ (or run `make clean-vendor`) to force a refresh.

set -euo pipefail

REVEAL_VERSION="${REVEAL_VERSION:-4.6.1}"
POINTER_VERSION="${POINTER_VERSION:-0.1.4}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/docs/content/assets/vendor"
STAMP="$VENDOR/.stamp"

mkdir -p "$VENDOR"

fetch_tarball() {
    # $1 = package name, $2 = version, $3 = destination dir (relative to VENDOR)
    local pkg="$1" ver="$2" dest="$VENDOR/$3"
    if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
        echo "  [skip] $pkg@$ver (already present in $dest)"
        return 0
    fi
    local url="https://registry.npmjs.org/${pkg}/-/${pkg}-${ver}.tgz"
    local tmp
    tmp="$(mktemp -d)"
    echo "  [get ] $pkg@$ver <- $url"
    curl -fsSL "$url" -o "$tmp/pkg.tgz"
    mkdir -p "$dest"
    tar -xzf "$tmp/pkg.tgz" -C "$tmp"
    # npm tarballs unpack to package/
    cp -R "$tmp/package/." "$dest/"
    rm -rf "$tmp"
}

fetch_fonts() {
    # Download the Google Fonts CSS with a modern-browser User-Agent so that
    # Google returns woff2 URLs, then mirror every woff2 file and rewrite the
    # CSS to use local relative paths.
    local dest="$VENDOR/fonts"
    local css="$dest/fonts.css"
    if [ -f "$css" ]; then
        echo "  [skip] Google fonts CSS (already at $css)"
        return 0
    fi
    mkdir -p "$dest"
    local url="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=Source+Serif+4:ital,wght@0,400;0,600;1,400&family=JetBrains+Mono:wght@400&display=swap"
    local ua="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    echo "  [get ] Google fonts CSS"
    curl -fsSL -A "$ua" "$url" -o "$css.orig"

    # Extract each font URL, download it, and rewrite the CSS.
    local i=0
    local tmpmap
    tmpmap="$(mktemp)"
    grep -oE "https://fonts\.gstatic\.com/[^)]+" "$css.orig" | sort -u | \
      while read -r furl; do
          i=$((i+1))
          local fname
          fname="$(basename "$furl")"
          # Prefix with an index so we don't get collisions across families.
          local local_name="${i}-${fname}"
          echo "  [get ] font $local_name"
          curl -fsSL -A "$ua" "$furl" -o "$dest/$local_name"
          printf '%s\t%s\n' "$furl" "$local_name" >> "$tmpmap"
      done

    cp "$css.orig" "$css"
    # Rewrite each remote URL to the local basename.
    while IFS=$'\t' read -r furl local_name; do
        # sed-safe: URLs contain no slashes-in-name issues once we escape /.
        local esc
        esc="$(printf '%s' "$furl" | sed 's/[\/&]/\\&/g')"
        sed -i "s/$esc/$local_name/g" "$css"
    done < "$tmpmap"
    rm -f "$tmpmap" "$css.orig"
}

echo "==> Vendoring reveal.js@$REVEAL_VERSION"
fetch_tarball "reveal.js" "$REVEAL_VERSION" "reveal.js"

echo "==> Vendoring reveal.js-pointer@$POINTER_VERSION"
fetch_tarball "reveal.js-pointer" "$POINTER_VERSION" "reveal.js-pointer"

echo "==> Vendoring Google Fonts"
fetch_fonts

date -u +"%Y-%m-%dT%H:%M:%SZ" > "$STAMP"
echo "==> Vendor tree ready at $VENDOR"
