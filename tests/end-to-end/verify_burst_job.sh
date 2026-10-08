#!/usr/bin/env bash
set -euo pipefail

: "${JOB_ID:?JOB_ID is required}"
: "${OUTPUT_FILE:?OUTPUT_FILE is required}"
: "${SOURCE_REGION:?SOURCE_REGION is required}"
: "${BURST_REGION:?BURST_REGION is required}"
: "${IDLE_TIMEOUT_MINUTES:?IDLE_TIMEOUT_MINUTES is required}"
: "${DEMO_UID_GID:?DEMO_UID_GID is required}"

deadline="$(( $(date +%s) + 900 ))"
states=()
while (( $(date +%s) < deadline )); do
  state="$(sacct -j "$JOB_ID" --noheader --parsable2 --format=State | head -n 1 | cut -d'|' -f1)"
  states+=("$state")
  [[ "$state" == COMPLETED* ]] && break
  [[ "$state" == FAILED* || "$state" == CANCELLED* || "$state" == TIMEOUT* ]] && {
    echo "Job entered terminal failure state: $state" >&2
    exit 3
  }
  sleep 10
done
[[ -f "$OUTPUT_FILE" ]] || { echo "Job output was not created within 15 minutes" >&2; exit 4; }

execution_node="$(sed -n 's/^execution_node=//p' "$OUTPUT_FILE")"
execution_region="$(sed -n 's/^execution_region=//p' "$OUTPUT_FILE")"
[[ -n "$execution_node" ]] || { echo "Execution node evidence is missing" >&2; exit 5; }
[[ "${execution_region,,}" == "${BURST_REGION,,}" ]] || {
  echo "Job ran in $execution_region rather than $BURST_REGION" >&2
  exit 5
}

scheduler_region="$(curl --fail --silent --noproxy '*' -H Metadata:true \
  'http://169.254.169.254/metadata/instance/compute/location?api-version=2025-04-07&format=text')"
[[ "${scheduler_region,,}" == "${SOURCE_REGION,,}" ]] || {
  echo "Scheduler is not in configured source region" >&2
  exit 5
}

[[ "$(stat -c '%u:%g' "$OUTPUT_FILE")" == "$DEMO_UID_GID:$DEMO_UID_GID" ]]
findmnt -rn /sched >/dev/null
findmnt -rn /shared >/dev/null
[[ "$(scontrol show nodes --json | jq '[.nodes[] | select(.state[0] != "DOWN")] | length')" -le 1 ]]

sleep "$(( IDLE_TIMEOUT_MINUTES * 60 + 120 ))"
scontrol show node "$execution_node" >/dev/null 2>&1 && {
  echo "Burst node still exists after idle timeout" >&2
  exit 6
}
scontrol ping | grep -Fq 'UP'
printf '%s\n' "${states[@]}" | grep -Eq 'PENDING|CONFIGURING|RUNNING'
