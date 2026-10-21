# shellcheck shell=bash
# Tests for verify-php-signature (run through tests/run.sh); the copy in docker-php/ must be
# identical. Each test makes throwaway signing keys, so nothing depends on the network or the
# real PHP keys.

VERIFY=php-fpm/docker-php/verify-php-signature

# new_key <name>: create a passphrase-less signing key in $KEYS_HOME, print its fingerprint
new_key() {
    GNUPGHOME=$KEYS_HOME gpg --batch --quiet --passphrase '' --quick-gen-key "$1 <$1@example.test>" ed25519 sign never 2>/dev/null
    GNUPGHOME=$KEYS_HOME gpg --batch --with-colons --list-keys "$1@example.test" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'
}

# sign <fingerprint> <file>: detached ASCII signature at <file>.asc
sign() {
    GNUPGHOME=$KEYS_HOME gpg --batch --quiet --yes --local-user "$1" --armor --detach-sign --output "$2.asc" "$2"
}

setup_keys() {
    WORK=$(dirname "$A")
    KEYS_HOME=$WORK/gnupg
    mkdir -m 700 "$KEYS_HOME"
    PINNED=$(new_key pinned)
    OTHER=$(new_key other)
    echo "php source" > "$WORK/php.tar.xz"
}

# export_keys <fingerprint>...: public keys into $WORK/keys.asc
export_keys() {
    GNUPGHOME=$KEYS_HOME gpg --batch --armor --export "$@" > "$WORK/keys.asc"
}

test_verify_accepts_pinned_signer() {
    setup_keys
    export_keys "$PINNED"
    sign "$PINNED" "$WORK/php.tar.xz"
    assert_ok "pinned signer" env GPG_KEYS="$PINNED" "$VERIFY" "$WORK/php.tar.xz" "$WORK/php.tar.xz.asc" "$WORK/keys.asc"
}

test_verify_rejects_unpinned_signer() {
    setup_keys
    export_keys "$PINNED" "$OTHER"
    sign "$OTHER" "$WORK/php.tar.xz"
    assert_fails "signer not in GPG_KEYS" env GPG_KEYS="$PINNED" "$VERIFY" "$WORK/php.tar.xz" "$WORK/php.tar.xz.asc" "$WORK/keys.asc"
}

test_verify_rejects_tampered_tarball() {
    setup_keys
    export_keys "$PINNED"
    sign "$PINNED" "$WORK/php.tar.xz"
    echo "tampered" >> "$WORK/php.tar.xz"
    assert_fails "tampered" env GPG_KEYS="$PINNED" "$VERIFY" "$WORK/php.tar.xz" "$WORK/php.tar.xz.asc" "$WORK/keys.asc"
}

test_verify_rejects_keyring_missing_a_pinned_key() {
    setup_keys
    export_keys "$PINNED"
    sign "$PINNED" "$WORK/php.tar.xz"
    assert_fails "pinned key not in keyring" env GPG_KEYS="$PINNED $OTHER" "$VERIFY" "$WORK/php.tar.xz" "$WORK/php.tar.xz.asc" "$WORK/keys.asc"
}

test_verify_rejects_empty_gpg_keys() {
    setup_keys
    export_keys "$PINNED"
    sign "$PINNED" "$WORK/php.tar.xz"
    assert_fails "empty GPG_KEYS" env GPG_KEYS="" "$VERIFY" "$WORK/php.tar.xz" "$WORK/php.tar.xz.asc" "$WORK/keys.asc"
}
