# shellcheck shell=bash
# Tests for scripts/php-release.sh (run through tests/run.sh)

test_release_parses_fixture() {
    assert_eq "8.5.12 08bc2eba2a588654ade1357174aa646b761556c862dda0678345ee29ed481209 security" \
        "$(scripts/php-release.sh < tests/fixtures/release-8.5.12.json)" parse
}

test_release_marks_non_security() {
    assert_eq "8.5.12 08bc2eba2a588654ade1357174aa646b761556c862dda0678345ee29ed481209 -" \
        "$(jq '.tags = []' tests/fixtures/release-8.5.12.json | scripts/php-release.sh)" "no security tag"
}

test_release_rejects_error_json() {
    assert_fails error sh -c 'scripts/php-release.sh < tests/fixtures/release-error.json'
    assert_eq "" "$(scripts/php-release.sh < tests/fixtures/release-error.json 2>/dev/null)" "no stdout on error"
}

test_release_rejects_empty_input() {
    assert_fails empty sh -c 'scripts/php-release.sh < /dev/null'
    assert_fails html sh -c 'echo "<html>" | scripts/php-release.sh'
}

test_release_rejects_rc_version() {
    assert_fails rc sh -c "jq '.version=\"8.5.13RC1\"' tests/fixtures/release-8.5.12.json | scripts/php-release.sh"
}

test_release_rejects_missing_tar_xz() {
    assert_fails "no tar.xz" sh -c "jq '.source |= map(select(.filename | endswith(\".tar.xz\") | not))' tests/fixtures/release-8.5.12.json | scripts/php-release.sh"
}

test_release_rejects_bad_sha() {
    assert_fails "bad sha" sh -c "jq '(.source[] | select(.filename | endswith(\".tar.xz\")) | .sha256) = \"deadbeef\"' tests/fixtures/release-8.5.12.json | scripts/php-release.sh"
}
