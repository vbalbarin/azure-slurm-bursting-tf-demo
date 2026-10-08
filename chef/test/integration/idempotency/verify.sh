#!/usr/bin/env bash
set -euo pipefail

: "${CYCLECLOUD_CONVERGE:?CYCLECLOUD_CONVERGE is required}"
: "${SCHEDULER_CONVERGE:?SCHEDULER_CONVERGE is required}"
: "${PROCESSOR_COMMAND:?PROCESSOR_COMMAND is required}"

"$CYCLECLOUD_CONVERGE"
cyclecloud_second="$("$CYCLECLOUD_CONVERGE" 2>&1)"
grep -Eq '0 resources updated|0/.* resources updated' <<<"$cyclecloud_second"

"$SCHEDULER_CONVERGE"
scheduler_second="$("$SCHEDULER_CONVERGE" 2>&1)"
grep -Eq '0 resources updated|0/.* resources updated' <<<"$scheduler_second"

processor_second="$(bash -c "$PROCESSOR_COMMAND")"
grep -Fq '"changed": false' <<<"$processor_second"
