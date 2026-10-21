#!/usr/bin/env bash
# Reads, bumps and checks the PHP source pin in the Dockerfiles: the GPG_KEYS, PHP_VERSION,
# PHP_URL/PHP_ASC_URL and PHP_SHA256 ENV lines of the stage ported from docker-library/php.
#
#   php-pin.sh get <dockerfile>                       print PHP_VERSION
#   php-pin.sh set <version> <sha256> <dockerfile>... pin a release in every file
#   php-pin.sh check <dockerfile>...                  pins are well-formed and identical
#   php-pin.sh is-newer <candidate> <current>         exit 0 if candidate is newer
set -euo pipefail

VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

die() { echo "php-pin: $*" >&2; exit 1; }
usage() { sed -n 's/^#   //p' "$0" >&2; exit 2; }

# pin_lines <dockerfile>: print the pin lines in a fixed order; fail unless each occurs once
pin_lines() {
    local file=$1 prefix count
    [ -f "$file" ] || die "$file: no such file"
    for prefix in 'ENV GPG_KEYS ' 'ENV PHP_VERSION ' 'ENV PHP_URL=' 'ENV PHP_SHA256='; do
        count=$(grep -c "^$prefix" "$file" || true)
        [ "$count" -eq 1 ] || die "$file: expected one '${prefix% }' line, found $count"
        grep "^$prefix" "$file"
    done
}

url_line() { # <version>
    local url="https://www.php.net/distributions/php-$1.tar.xz"
    echo "ENV PHP_URL=\"$url\" PHP_ASC_URL=\"$url.asc\""
}

cmd_get() {
    [ $# -eq 1 ] || usage
    local version
    version=$(pin_lines "$1" | sed -n 's/^ENV PHP_VERSION //p')
    echo "$version"
}

cmd_set() {
    [ $# -ge 3 ] || usage
    local version=$1 sha=$2 file
    shift 2
    [[ $version =~ $VERSION_RE ]] || die "not a release version: '$version'"
    [[ $sha =~ ^[0-9a-f]{64}$ ]] || die "not a SHA-256: '$sha'"
    # Validate every file before rewriting any, so a malformed file leaves all of them untouched
    for file in "$@"; do pin_lines "$file" >/dev/null; done
    for file in "$@"; do
        sed -i \
            -e "s|^ENV PHP_VERSION .*|ENV PHP_VERSION $version|" \
            -e "s|^ENV PHP_URL=.*|$(url_line "$version")|" \
            -e "s|^ENV PHP_SHA256=.*|ENV PHP_SHA256=\"$sha\"|" \
            "$file"
    done
}

cmd_check() {
    [ $# -ge 1 ] || usage
    local file lines version first="" first_file=""
    for file in "$@"; do
        lines=$(pin_lines "$file")
        version=$(sed -n 's/^ENV PHP_VERSION //p' <<<"$lines")
        [[ $version =~ $VERSION_RE ]] || die "$file: PHP_VERSION '$version' is not a release version"
        grep -qxF "$(url_line "$version")" <<<"$lines" \
            || die "$file: PHP_URL/PHP_ASC_URL do not point at php-$version.tar.xz"
        grep -qxE 'ENV PHP_SHA256="[0-9a-f]{64}"' <<<"$lines" || die "$file: PHP_SHA256 is not a SHA-256"
        if [ -z "$first_file" ]; then
            first=$lines
            first_file=$file
        elif [ "$lines" != "$first" ]; then
            die "$file: pin differs from $first_file"
        fi
    done
    echo "pin OK: $version"
}

cmd_is_newer() {
    [ $# -eq 2 ] || usage
    if ! [[ $1 =~ $VERSION_RE && $2 =~ $VERSION_RE ]]; then
        echo "php-pin: is-newer needs two X.Y.Z versions, got '$1' '$2'" >&2
        exit 2
    fi
    [ "$1" != "$2" ] && [ "$(printf '%s\n' "$2" "$1" | sort -V | tail -1)" = "$1" ]
}

command=${1:-}
[ $# -gt 0 ] && shift
case "$command" in
    get) cmd_get "$@" ;;
    set) cmd_set "$@" ;;
    check) cmd_check "$@" ;;
    is-newer) cmd_is_newer "$@" ;;
    *) usage ;;
esac
