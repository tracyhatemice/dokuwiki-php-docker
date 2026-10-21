#!/usr/bin/env bash
# Parses a php.net releases API response (https://www.php.net/releases/index.php?json&version=X.Y)
# from stdin and prints "<version> <php-<version>.tar.xz SHA-256> <security|->".
# Exits 1 with nothing on stdout if the response is not a usable release.
set -euo pipefail

die() { echo "php-release: $*" >&2; exit 1; }

json=$(cat)
[ -n "$json" ] || die "empty response"
jq -e 'type == "object"' >/dev/null 2>&1 <<<"$json" || die "response is not a JSON object"

error=$(jq -r '.error // empty' <<<"$json")
[ -z "$error" ] || die "php.net: $error"

version=$(jq -r '.version // empty' <<<"$json")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "not a release version: '$version'"

sha=$(jq -r --arg file "php-$version.tar.xz" \
    '[.source[]? | select(.filename == $file) | .sha256] | first // empty' <<<"$json")
[[ $sha =~ ^[0-9a-f]{64}$ ]] || die "no valid SHA-256 for php-$version.tar.xz: '$sha'"

security=$(jq -r 'if (.tags // []) | index("security") then "security" else "-" end' <<<"$json")

echo "$version $sha $security"
