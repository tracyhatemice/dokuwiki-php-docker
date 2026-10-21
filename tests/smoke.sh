#!/usr/bin/env bash
# Smoke test for the PHP images: version, modules, ini paths, image config, and a
# request served end to end.
#
#   tests/smoke.sh apache <image> <expected-php-version>
#   tests/smoke.sh fpm    <image> <expected-php-version> <web-image>
#
# <web-image> is the dokuwiki-apache image that reaches PHP-FPM over the shared socket.
set -uo pipefail

usage() { echo "usage: $0 apache <image> <version> | fpm <image> <version> <web-image>" >&2; exit 2; }

MODE=${1:-}; IMAGE=${2:-}; VERSION=${3:-}; WEB_IMAGE=${4:-}
case "$MODE" in
    apache) [ $# -eq 3 ] || usage ;;
    fpm) [ $# -eq 4 ] || usage ;;
    *) usage ;;
esac

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FAILED=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; FAILED=1; }

# Containers, volume and docroot created below are removed on exit
CONTAINERS=()
VOLUME=""
DOCROOT=""
cleanup() {
    [ ${#CONTAINERS[@]} -eq 0 ] || docker rm -f "${CONTAINERS[@]}" >/dev/null 2>&1
    [ -z "$VOLUME" ] || docker volume rm "$VOLUME" >/dev/null 2>&1
    [ -z "$DOCROOT" ] || rm -rf "$DOCROOT"
}
trap cleanup EXIT

php_cli() { docker run --rm --entrypoint php "$IMAGE" "$@"; }

# 1. PHP version
actual=$(php_cli -r 'echo PHP_VERSION;' 2>&1)
if [ "$actual" = "$VERSION" ]; then pass "PHP version $actual"; else fail "PHP version: expected $VERSION, got $actual"; fi

# 2. Module list matches the baseline taken from the official-base images
if modules_diff=$(diff "$ROOT/tests/expected-modules.txt" <(php_cli -m 2>&1)); then
    pass "php -m matches tests/expected-modules.txt"
else
    fail "php -m differs from tests/expected-modules.txt:"; echo "$modules_diff"
fi

# 3. Config file locations
ini=$(php_cli --ini 2>&1)
for line in \
    'Configuration File (php.ini) Path: "/usr/local/etc/php"' \
    'Loaded Configuration File:         "/usr/local/etc/php/php.ini"' \
    'Scan for additional .ini files in: "/usr/local/etc/php/conf.d"'
do
    if grep -qxF "$line" <<<"$ini"; then pass "php --ini: $line"; else fail "php --ini lacks: $line"; fi
done

# 4. Image config
if [ "$MODE" = apache ]; then
    expected_config=(
        'Entrypoint=["docker-php-entrypoint"]'
        'Cmd=["apache2-foreground"]'
        'StopSignal=SIGWINCH'
        'ExposedPorts={"80/tcp":{}}'
        'WorkingDir=/var/www/html'
        'User=""'
    )
else
    expected_config=(
        'Entrypoint=["docker-php-entrypoint"]'
        'Cmd=["php-fpm"]'
        'StopSignal=SIGQUIT'
        'ExposedPorts={"9000/tcp":{}}'
        'WorkingDir=/var/www/html'
        'User="www-data"'
    )
fi
config=$(docker image inspect "$IMAGE" --format \
'Entrypoint={{json .Config.Entrypoint}}
Cmd={{json .Config.Cmd}}
StopSignal={{.Config.StopSignal}}
ExposedPorts={{json .Config.ExposedPorts}}
WorkingDir={{.Config.WorkingDir}}
User={{json .Config.User}}')
for want in "${expected_config[@]}"; do
    got=$(grep "^${want%%=*}=" <<<"$config")
    if [ "$got" = "$want" ]; then pass "config $want"; else fail "config: expected $want, got $got"; fi
done

# 5. A .php request is served end to end
DOCROOT=$(mktemp -d)
printf '%s\n' "<?php echo PHP_VERSION, ' ', PHP_SAPI;" > "$DOCROOT/index.php"
chmod 755 "$DOCROOT"; chmod 644 "$DOCROOT/index.php"

# fetch <port>: prints response headers and body, retrying for up to 30 seconds
fetch() {
    local _
    for _ in $(seq 30); do
        if curl -fsS -i "http://127.0.0.1:$1/index.php" 2>/dev/null; then return 0; fi
        sleep 1
    done
    return 1
}
body_of() { sed '1,/^\r\{0,1\}$/d' <<<"$1"; }

if [ "$MODE" = apache ]; then
    c=$(docker run -d -p 127.0.0.1::80 -v "$DOCROOT:/var/www/html:ro" "$IMAGE")
    CONTAINERS+=("$c")
    port=$(docker port "$c" 80/tcp | head -1 | sed 's/.*://')
    response=$(fetch "$port") || true
    body=$(body_of "$response")
    if [ "$body" = "$VERSION apache2handler" ]; then pass "served: $body"; else fail "served: expected '$VERSION apache2handler', got '$body'"; fi
    if grep -qi '^X-Content-Type-Options: nosniff' <<<"$response"; then pass "header X-Content-Type-Options: nosniff"; else fail "header X-Content-Type-Options: nosniff missing"; fi
    loaded=$(docker exec "$c" apache2ctl -M 2>&1)
    for module in mpm_prefork_module php_module; do
        if grep -qw "$module" <<<"$loaded"; then pass "apache module $module"; else fail "apache module $module not loaded"; fi
    done
else
    VOLUME=$(docker volume create)
    fpm=$(docker run -d -v "$VOLUME:/run/php-fpm" -v "$DOCROOT:/var/www/html:ro" "$IMAGE")
    CONTAINERS+=("$fpm")
    web=$(docker run -d -p 127.0.0.1::8080 -v "$VOLUME:/run/php-fpm" -v "$DOCROOT:/var/www/html:ro" "$WEB_IMAGE")
    CONTAINERS+=("$web")
    port=$(docker port "$web" 8080/tcp | head -1 | sed 's/.*://')
    response=$(fetch "$port") || true
    body=$(body_of "$response")
    if [ "$body" = "$VERSION fpm-fcgi" ]; then pass "served: $body"; else fail "served: expected '$VERSION fpm-fcgi', got '$body'"; fi
    uid=$(docker exec "$fpm" grep '^Uid:' /proc/1/status | awk '{print $2}')
    if [ "$uid" = 33 ]; then pass "php-fpm master runs as uid 33 (www-data)"; else fail "php-fpm master uid: expected 33, got '$uid'"; fi
fi

exit "$FAILED"
