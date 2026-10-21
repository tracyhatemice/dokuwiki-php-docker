#!/usr/bin/env bash
# Decides whether an image workflow run builds and whether it skips the build cache;
# writes skip=true|false and no_cache=true|false to $GITHUB_OUTPUT.
#
# Env: EVENT (github.event_name), SCHEDULE (github.event.schedule), FORCE,
#      IMAGE_REF (the published :latest), NEW_BASE (current base image digest),
#      PIN_FILE (optional: Dockerfile whose PHP pin the published image must carry)
set -euo pipefail

# Must match the weekly cron in the image workflows' on.schedule
WEEKLY_CRON='0 4 * * 0'

output() { echo "$1" >> "$GITHUB_OUTPUT"; }

if [ "${EVENT}" = "schedule" ] && [ "${SCHEDULE:-}" = "${WEEKLY_CRON}" ]; then
    echo "Weekly rebuild: build without cache."
    output skip=false
    output no_cache=true
    exit 0
fi
output no_cache=false

if [ "${EVENT}" != "schedule" ] || [ "${FORCE:-}" = "true" ]; then
    echo "Trigger=${EVENT} force=${FORCE:-}: build."
    output skip=false
    exit 0
fi

# Schedule trigger: skip if the previous build used the same base digest (and PHP pin).
if ! docker pull "${IMAGE_REF}" >/dev/null 2>&1; then
    echo "No previous :latest in registry; building."
    output skip=false
    exit 0
fi
PREV=$(docker inspect "${IMAGE_REF}" \
    --format '{{ index .Config.Labels "org.opencontainers.image.base.digest" }}' \
    2>/dev/null || true)
echo "Previous base digest: ${PREV:-<none>}"
echo "Current  base digest: ${NEW_BASE}"
if [ -z "${PREV}" ] || [ "${PREV}" != "${NEW_BASE}" ]; then
    output skip=false
    exit 0
fi

# A merged PHP bump whose build failed leaves the old PHP in :latest; retry it
if [ -n "${PIN_FILE:-}" ]; then
    WANT="php:$("$(dirname "$0")/php-pin.sh" get "${PIN_FILE}")"
    HAVE=$(docker inspect "${IMAGE_REF}" --format '{{ index .Config.Labels "Version" }}' 2>/dev/null || true)
    echo "Published: ${HAVE:-<none>}; pinned: ${WANT}"
    if [ "${HAVE}" != "${WANT}" ]; then
        output skip=false
        exit 0
    fi
fi
echo "Base unchanged; skipping rebuild."
output skip=true
