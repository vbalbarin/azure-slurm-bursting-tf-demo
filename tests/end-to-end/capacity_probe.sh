#!/usr/bin/env bash
set -euo pipefail
umask 077

for command in terraform sha256sum jq timeout; do
  command -v "$command" >/dev/null || { echo "Missing required command: $command" >&2; exit 2; }
done

action="${1:-}"
case "$action" in
  plan|apply|cleanup-plan|cleanup) ;;
  *) echo "Usage: $0 {plan|apply|cleanup-plan|cleanup}" >&2; exit 2 ;;
esac

: "${PROBE_TFVARS_FILE:?PROBE_TFVARS_FILE is required}"
: "${PROBE_PLAN_FILE:?PROBE_PLAN_FILE is required}"
: "${PROBE_APPROVAL_FILE:?PROBE_APPROVAL_FILE is required}"
: "${PROBE_DESTROY_PLAN_FILE:?PROBE_DESTROY_PLAN_FILE is required}"
: "${PROBE_CLEANUP_APPROVAL_FILE:?PROBE_CLEANUP_APPROVAL_FILE is required}"
: "${PROBE_EVIDENCE_DIR:?PROBE_EVIDENCE_DIR is required}"

probe_timeout_seconds="${PROBE_TIMEOUT_SECONDS:-900}"
root="terraform/capacity-probe"
mkdir -p "$PROBE_EVIDENCE_DIR"

classify_failure() {
  local log_file="$1"
  if grep -Eqi 'ZonalAllocationFailed' "$log_file"; then
    printf 'zonal_allocation_failed'
  elif grep -Eqi 'AllocationFailed|OverconstrainedAllocationRequest' "$log_file"; then
    printf 'allocation_failed'
  elif grep -Eqi 'OperationNotAllowed|Quota' "$log_file"; then
    printf 'quota_failed'
  elif grep -Eqi 'SkuNotAvailable' "$log_file"; then
    printf 'sku_unavailable'
  else
    printf 'unknown'
  fi
}

verify_approval() {
  local plan_file="$1" approval_file="$2"
  local actual approved
  [[ -f "$plan_file" ]] || { echo "Reviewed plan does not exist: $plan_file" >&2; exit 10; }
  [[ -f "$approval_file" ]] || { echo "Approval does not exist: $approval_file" >&2; exit 10; }
  actual="$(sha256sum "$plan_file" | awk '{print $1}')"
  approved="$(jq -er '.plan_digest' "$approval_file")"
  [[ "$(jq -er '.cost_acknowledged' "$approval_file")" == "true" ]] || {
    echo "Approval must acknowledge temporary Azure cost" >&2
    exit 10
  }
  [[ "$actual" == "$approved" ]] || {
    echo "Approval digest does not match the exact probe plan" >&2
    exit 11
  }
}

case "$action" in
  plan)
    terraform -chdir="$root" fmt -check
    terraform -chdir="$root" validate
    terraform -chdir="$root" plan -input=false -var-file="$PROBE_TFVARS_FILE" -out="$PROBE_PLAN_FILE"
    sha256sum "$PROBE_PLAN_FILE" | tee "$PROBE_EVIDENCE_DIR/probe-plan.sha256"
    terraform -chdir="$root" show -no-color "$PROBE_PLAN_FILE"
    ;;
  apply)
    verify_approval "$PROBE_PLAN_FILE" "$PROBE_APPROVAL_FILE"
    started_at="$(date -u +%FT%TZ)"
    set +e
    timeout --foreground "${probe_timeout_seconds}s" \
      terraform -chdir="$root" apply -input=false "$PROBE_PLAN_FILE" \
      >"$PROBE_EVIDENCE_DIR/probe-apply.log" 2>&1
    status="$?"
    set -e
    completed_at="$(date -u +%FT%TZ)"
    if [[ "$status" -eq 0 ]]; then
      terraform -chdir="$root" output -json probe |
        jq --arg started_at "$started_at" --arg completed_at "$completed_at" \
          '. + {allocation_state:"allocated",started_at:$started_at,completed_at:$completed_at,
                guarantee:"point_in_time_only",cleanup_state:"pending"}' \
          >"$PROBE_EVIDENCE_DIR/capacity-probe.json"
    else
      failure_class="$(classify_failure "$PROBE_EVIDENCE_DIR/probe-apply.log")"
      [[ "$status" -eq 124 ]] && failure_class="timed_out"
      jq -n --arg started_at "$started_at" --arg completed_at "$completed_at" \
        --arg failure_class "$failure_class" --argjson exit_status "$status" \
        '{allocation_state:"failed",failure_class:$failure_class,exit_status:$exit_status,
          started_at:$started_at,completed_at:$completed_at,guarantee:"point_in_time_only",
          cleanup_state:"pending"}' >"$PROBE_EVIDENCE_DIR/capacity-probe.json"
      exit "$status"
    fi
    ;;
  cleanup-plan)
    terraform -chdir="$root" plan -destroy -input=false \
      -var-file="$PROBE_TFVARS_FILE" -out="$PROBE_DESTROY_PLAN_FILE"
    sha256sum "$PROBE_DESTROY_PLAN_FILE" | tee "$PROBE_EVIDENCE_DIR/probe-destroy-plan.sha256"
    terraform -chdir="$root" show -no-color "$PROBE_DESTROY_PLAN_FILE"
    ;;
  cleanup)
    verify_approval "$PROBE_DESTROY_PLAN_FILE" "$PROBE_CLEANUP_APPROVAL_FILE"
    timeout --foreground "${probe_timeout_seconds}s" \
      terraform -chdir="$root" apply -input=false "$PROBE_DESTROY_PLAN_FILE" \
      >"$PROBE_EVIDENCE_DIR/probe-cleanup.log" 2>&1
    if [[ -n "$(terraform -chdir="$root" state list)" ]]; then
      echo "Capacity-probe cleanup could not be verified" >&2
      exit 12
    fi
    cleaned_at="$(date -u +%FT%TZ)"
    jq --arg cleaned_at "$cleaned_at" \
      '.cleanup_state="verified" | .cleaned_at=$cleaned_at' \
      "$PROBE_EVIDENCE_DIR/capacity-probe.json" \
      >"$PROBE_EVIDENCE_DIR/capacity-probe.json.tmp"
    mv "$PROBE_EVIDENCE_DIR/capacity-probe.json.tmp" \
      "$PROBE_EVIDENCE_DIR/capacity-probe.json"
    ;;
esac
