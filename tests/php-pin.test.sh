# shellcheck shell=bash
# Tests for scripts/php-pin.sh (run through tests/run.sh)

test_get_reads_version() {
    assert_eq 8.5.11 "$(scripts/php-pin.sh get "$A")" get
}

test_get_fails_without_pin() {
    sed -i '/^ENV PHP_VERSION /d' "$A"
    assert_fails "missing PHP_VERSION" scripts/php-pin.sh get "$A"
}

test_set_rewrites_all_lines() {
    scripts/php-pin.sh set 8.5.12 "$SHA" "$A" "$B"
    assert_eq 8.5.12 "$(scripts/php-pin.sh get "$B")" version
    assert_ok "url+asc" grep -qx 'ENV PHP_URL="https://www.php.net/distributions/php-8.5.12.tar.xz" PHP_ASC_URL="https://www.php.net/distributions/php-8.5.12.tar.xz.asc"' "$A"
    assert_ok sha grep -qx 'ENV PHP_SHA256="08bc2eba2a588654ade1357174aa646b761556c862dda0678345ee29ed481209"' "$A"
    assert_ok "other lines kept" grep -qx 'COPY docker-php-source /usr/local/bin/' "$A"
    assert_eq "pin OK: 8.5.12" "$(scripts/php-pin.sh check "$A" "$B")" "check after set"
}

test_set_rejects_bad_version() {
    assert_fails rc scripts/php-pin.sh set 8.5.13RC1 "$SHA" "$A"
    assert_fails short scripts/php-pin.sh set 8.5 "$SHA" "$A"
    assert_fails sha scripts/php-pin.sh set 8.5.12 deadbeef "$A"
    assert_eq 8.5.11 "$(scripts/php-pin.sh get "$A")" unchanged
}

test_set_is_all_or_nothing() {
    sed -i '/PHP_SHA256/d' "$B"
    assert_fails malformed scripts/php-pin.sh set 8.5.12 "$SHA" "$A" "$B"
    assert_eq 8.5.11 "$(scripts/php-pin.sh get "$A")" "A untouched"
}

test_check_passes_on_matching_pins() {
    assert_eq "pin OK: 8.5.11" "$(scripts/php-pin.sh check "$A" "$B")" check
}

test_check_detects_mismatch() {
    sed -i 's/^ENV PHP_VERSION .*/ENV PHP_VERSION 8.5.10/' "$B"
    assert_fails mismatch scripts/php-pin.sh check "$A" "$B"
}

test_check_detects_url_drift() {
    sed -i 's/php-8.5.11.tar.xz"/php-8.5.10.tar.xz"/' "$A"
    assert_fails drift scripts/php-pin.sh check "$A"
}

test_check_detects_missing_gpg_keys() {
    sed -i '/^ENV GPG_KEYS /d' "$A"
    assert_fails "missing GPG_KEYS" scripts/php-pin.sh check "$A"
}

test_is_newer_numeric_not_lexical() {
    assert_ok "10>9" scripts/php-pin.sh is-newer 8.5.10 8.5.9
    assert_fails equal scripts/php-pin.sh is-newer 8.5.12 8.5.12
    assert_fails older scripts/php-pin.sh is-newer 8.5.11 8.5.12
}

test_is_newer_rejects_malformed() {
    scripts/php-pin.sh is-newer 8.5.13RC1 8.5.12 >/dev/null 2>&1
    assert_eq 2 "$?" "rc candidate exit code"
    scripts/php-pin.sh is-newer 8.5.13 "" >/dev/null 2>&1
    assert_eq 2 "$?" "empty current exit code"
}
