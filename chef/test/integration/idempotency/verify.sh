#!/usr/bin/env bash
set -euo pipefail

: "${CYCLECLOUD_CONVERGE:?CYCLECLOUD_CONVERGE is required}"
: "${SCHEDULER_CONVERGE:?SCHEDULER_CONVERGE is required}"
: "${PROCESSOR_COMMAND:?PROCESSOR_COMMAND is required}"
: "${CYCLECLOUD_STAGED_DIR:?CYCLECLOUD_STAGED_DIR is required}"
: "${SCHEDULER_STAGED_DIR:?SCHEDULER_STAGED_DIR is required}"

digest_tree() {
  local directory="$1"
  [[ -d "$directory" ]] || {
    printf 'Staged release directory does not exist: %s\n' "$directory" >&2
    return 2
  }
  (
    cd "$directory"
    find . -type f -print0 |
      sort -z |
      xargs -0 -r sha256sum |
      sha256sum |
      awk '{print $1}'
  )
}

"$CYCLECLOUD_CONVERGE"
cyclecloud_digest_before="$(digest_tree "$CYCLECLOUD_STAGED_DIR")"
cyclecloud_second="$("$CYCLECLOUD_CONVERGE" 2>&1)"
grep -Eq '0 resources updated|0/.* resources updated' <<<"$cyclecloud_second"
[[ "$(digest_tree "$CYCLECLOUD_STAGED_DIR")" == "$cyclecloud_digest_before" ]] || {
  echo "CycleCloud staged release changed during idempotency verification" >&2
  exit 1
}

"$SCHEDULER_CONVERGE"
scheduler_digest_before="$(digest_tree "$SCHEDULER_STAGED_DIR")"
scheduler_second="$("$SCHEDULER_CONVERGE" 2>&1)"
grep -Eq '0 resources updated|0/.* resources updated' <<<"$scheduler_second"
[[ "$(digest_tree "$SCHEDULER_STAGED_DIR")" == "$scheduler_digest_before" ]] || {
  echo "Scheduler staged release changed during idempotency verification" >&2
  exit 1
}

processor_second="$(bash -c "$PROCESSOR_COMMAND")"
grep -Fq '"changed": false' <<<"$processor_second"
