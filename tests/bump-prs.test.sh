# shellcheck shell=bash
# Tests for scripts/bump-prs.sh (run through tests/run.sh), with a stub gh that returns
# canned `gh pr list --json` output and logs its arguments.

# stub_gh <json>: put a gh on PATH that prints <json>
stub_gh() {
    STUB=$(dirname "$A")/bin
    mkdir -p "$STUB"
    printf '%s\n' "$1" > "$STUB/prs.json"
    printf '#!/bin/sh\necho "$*" >> "%s/gh.log"\ncat "%s/prs.json"\n' "$STUB" "$STUB" > "$STUB/gh"
    chmod +x "$STUB/gh"
    PATH="$STUB:$PATH"
}
own() { printf '{"number":%s,"headRefName":"%s","isCrossRepository":false}' "$1" "$2"; }
fork() { printf '{"number":%s,"headRefName":"%s","isCrossRepository":true}' "$1" "$2"; }

test_proposed_counts_own_pr() {
    stub_gh "[$(own 1 php-bump/8.5.13)]"
    assert_eq yes "$(scripts/bump-prs.sh proposed php-bump/8.5.13)" "own PR"
}

test_proposed_ignores_fork_pr() {
    stub_gh "[$(fork 2 php-bump/8.5.13)]"
    assert_eq no "$(scripts/bump-prs.sh proposed php-bump/8.5.13)" "fork PR with the same branch name"
}

test_proposed_none() {
    stub_gh "[]"
    assert_eq no "$(scripts/bump-prs.sh proposed php-bump/8.5.13)" "no PR"
}

test_proposed_fails_when_gh_fails() {
    # A failed query must not read as "not proposed", or the watcher opens a duplicate
    stub_gh "[]"
    printf '#!/bin/sh\necho "gh: HTTP 502" >&2\nexit 1\n' > "$STUB/gh"
    assert_fails "gh error" scripts/bump-prs.sh proposed php-bump/8.5.13
    assert_eq "" "$(scripts/bump-prs.sh proposed php-bump/8.5.13 2>/dev/null)" "no answer on gh error"
}

test_open_ignores_fork_pr() {
    stub_gh "[$(fork 2 php-bump/8.5.13),$(own 3 php-bump/8.5.13)]"
    assert_eq 3 "$(scripts/bump-prs.sh open php-bump/8.5.13)" "open own PR"
}

test_open_none_when_only_fork() {
    stub_gh "[$(fork 2 php-bump/8.5.13)]"
    assert_eq "" "$(scripts/bump-prs.sh open php-bump/8.5.13)" "no own open PR"
}

test_superseded_lists_only_own_other_bumps() {
    stub_gh "[$(own 5 php-bump/8.5.12),$(own 6 php-bump/8.5.13),$(fork 7 php-bump/8.5.11),$(own 8 feature-x)]"
    assert_eq 5 "$(scripts/bump-prs.sh superseded main php-bump/8.5.13)" superseded
}

test_queries_request_cross_repository_field() {
    # Without the field in --json, real gh output would make every PR look like our own
    stub_gh "[]"
    scripts/bump-prs.sh proposed php-bump/8.5.13 >/dev/null
    scripts/bump-prs.sh open php-bump/8.5.13 >/dev/null
    scripts/bump-prs.sh superseded main php-bump/8.5.13 >/dev/null
    assert_eq 3 "$(grep -c -- '--json [^ ]*isCrossRepository' "$STUB/gh.log")" "queries asking for isCrossRepository"
}
