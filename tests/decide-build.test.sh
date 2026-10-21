# shellcheck shell=bash
# Tests for scripts/decide-build.sh (run through tests/run.sh), with a stub docker standing
# in for the published :latest image. $A is a Dockerfile pinned to PHP 8.5.11.

# stub_docker <pull-exit-code> <base-digest-label> <Version-label>
stub_docker() {
    STUB=$(dirname "$A")/bin
    mkdir -p "$STUB"
    cat > "$STUB/docker" <<EOF
#!/bin/sh
case "\$1" in
    pull) exit $1 ;;
    inspect)
        case "\$*" in
            *base.digest*) echo "$2" ;;
            *Version*) echo "$3" ;;
        esac ;;
esac
EOF
    chmod +x "$STUB/docker"
    PATH="$STUB:$PATH"
}

# decide <VAR=value>...: run the script, print its GITHUB_OUTPUT lines joined by spaces
decide() {
    local out
    out=$(dirname "$A")/github-output
    : > "$out"
    env GITHUB_OUTPUT="$out" IMAGE_REF=ghcr.io/owner/image:latest NEW_BASE=sha256:new "$@" \
        scripts/decide-build.sh >/dev/null
    tr '\n' ' ' < "$out"
}

DAILY='0 0 * * *'

test_decide_weekly_builds_without_cache() {
    assert_eq "skip=false no_cache=true " "$(decide EVENT=schedule SCHEDULE='0 4 * * 0')" weekly
}

test_decide_push_builds_with_cache() {
    assert_eq "no_cache=false skip=false " "$(decide EVENT=push)" push
}

test_decide_nightly_skips_when_nothing_changed() {
    stub_docker 0 sha256:new php:8.5.11
    assert_eq "no_cache=false skip=true " "$(decide EVENT=schedule SCHEDULE="$DAILY" PIN_FILE="$A")" unchanged
}

test_decide_nightly_builds_on_new_base() {
    stub_docker 0 sha256:old php:8.5.11
    assert_eq "no_cache=false skip=false " "$(decide EVENT=schedule SCHEDULE="$DAILY" PIN_FILE="$A")" "new base"
}

test_decide_nightly_builds_when_pin_is_unpublished() {
    # A merged bump whose push build failed: :latest still has the old PHP
    stub_docker 0 sha256:new php:8.5.10
    assert_eq "no_cache=false skip=false " "$(decide EVENT=schedule SCHEDULE="$DAILY" PIN_FILE="$A")" "unpublished pin"
}

test_decide_nightly_without_pin_file_ignores_version() {
    stub_docker 0 sha256:new httpd:2.4
    assert_eq "no_cache=false skip=true " "$(decide EVENT=schedule SCHEDULE="$DAILY")" "no pin file"
}

test_decide_nightly_builds_without_previous_image() {
    stub_docker 1 "" ""
    assert_eq "no_cache=false skip=false " "$(decide EVENT=schedule SCHEDULE="$DAILY" PIN_FILE="$A")" "no :latest"
}
