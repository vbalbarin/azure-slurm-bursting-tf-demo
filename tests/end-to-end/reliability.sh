#!/usr/bin/env bash
set -euo pipefail

: "${RUN_BURST_DEMO:?RUN_BURST_DEMO is required}"
: "${EVIDENCE_DIR:?EVIDENCE_DIR is required}"
mkdir -p "$EVIDENCE_DIR"

successes=0
capacity_failures=0
product_failures=0
for run in $(seq 1 10); do
  log="$EVIDENCE_DIR/reliability-$run.log"
  if "$RUN_BURST_DEMO" >"$log" 2>&1; then
    successes="$((successes + 1))"
  elif grep -Eqi 'AllocationFailed|SkuNotAvailable|regional capacity' "$log"; then
    capacity_failures="$((capacity_failures + 1))"
  else
    product_failures="$((product_failures + 1))"
  fi
done

eligible="$((10 - capacity_failures))"
(( eligible > 0 && successes * 10 >= eligible * 9 )) || {
  echo "First-submission reliability below 9/10: successes=$successes capacity_exclusions=$capacity_failures product_failures=$product_failures" >&2
  exit 1
}
jq -n --argjson successes "$successes" --argjson capacity_failures "$capacity_failures" \
  --argjson product_failures "$product_failures" \
  '{successes:$successes, capacity_failures:$capacity_failures, product_failures:$product_failures}'
