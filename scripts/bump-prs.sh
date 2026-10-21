#!/usr/bin/env bash
# Queries the PHP release watcher's bump PRs (branches named php-bump/<version>). Only PRs
# from this repository's own branches count: anyone can open a fork PR from a branch with
# the same name.
#
#   bump-prs.sh proposed <branch>            print yes if a PR from <branch> exists in any state, else no
#   bump-prs.sh open <branch>                print the number of the open PR from <branch>, if any
#   bump-prs.sh superseded <base> <branch>   print open php-bump/* PRs into <base> other than <branch>
set -euo pipefail

FIELDS=number,headRefName,isCrossRepository
OWN='map(select(.isCrossRepository == false))'

usage() { sed -n 's/^#   //p' "$0" >&2; exit 2; }

command=${1:-}
[ $# -gt 0 ] && shift
case "$command" in
    proposed)
        [ $# -eq 1 ] || usage
        prs=$(gh pr list --head "$1" --state all --limit 100 --json "$FIELDS")
        jq -r "$OWN | if length > 0 then \"yes\" else \"no\" end" <<<"$prs"
        ;;
    open)
        [ $# -eq 1 ] || usage
        gh pr list --head "$1" --state open --limit 100 --json "$FIELDS" | jq -r "$OWN | .[0].number // empty"
        ;;
    superseded)
        [ $# -eq 2 ] || usage
        gh pr list --base "$1" --state open --limit 100 --json "$FIELDS" \
            | jq -r --arg branch "$2" \
                "$OWN"' | .[] | select(.headRefName | startswith("php-bump/")) | select(.headRefName != $branch) | .number'
        ;;
    *) usage ;;
esac
