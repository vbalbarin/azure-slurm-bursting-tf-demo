#!/usr/bin/env bash
set -euo pipefail
umask 077

for command in terraform sha256sum jq date; do
  command -v "$command" >/dev/null || { echo "Missing required command: $command" >&2; exit 2; }
done

: "${TFVARS_FILE:?TFVARS_FILE is required}"
: "${PLAN_FILE:?PLAN_FILE is required}"
: "${APPROVAL_FILE:?APPROVAL_FILE is required}"
: "${PREFLIGHT_RESULTS_FILE:?PREFLIGHT_RESULTS_FILE is required}"
: "${CAPACITY_PROBE_RESULTS_FILE:?CAPACITY_PROBE_RESULTS_FILE is required}"
: "${EVIDENCE_DIR:?EVIDENCE_DIR is required}"

[[ -f "$TFVARS_FILE" ]] || { echo "TFVARS_FILE does not exist" >&2; exit 2; }
[[ -f "$PREFLIGHT_RESULTS_FILE" ]] || { echo "PREFLIGHT_RESULTS_FILE does not exist" >&2; exit 2; }
[[ -f "$CAPACITY_PROBE_RESULTS_FILE" ]] || { echo "CAPACITY_PROBE_RESULTS_FILE does not exist" >&2; exit 2; }
[[ -f "$PLAN_FILE" ]] || { echo "PLAN_FILE does not exist; create and review it before provisioning" >&2; exit 2; }
[[ -f "$APPROVAL_FILE" ]] || { echo "APPROVAL_FILE does not exist" >&2; exit 10; }
[[ "$PLAN_FILE" != *.tfvars* ]] || { echo "PLAN_FILE must not be a variable file" >&2; exit 2; }
mkdir -p "$EVIDENCE_DIR"

terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate

plan_digest="$(sha256sum "$PLAN_FILE" | awk '{print $1}')"
preflight_digest="$(sha256sum "$PREFLIGHT_RESULTS_FILE" | awk '{print $1}')"
capacity_probe_digest="$(sha256sum "$CAPACITY_PROBE_RESULTS_FILE" | awk '{print $1}')"
printf '%s\n' "$plan_digest" >"$EVIDENCE_DIR/plan.sha256"
terraform -chdir=terraform show -json "$PLAN_FILE" >"$EVIDENCE_DIR/plan.json"

approved_digest="$(jq -er '.plan_digest' "$APPROVAL_FILE")"
approved_preflight_digest="$(jq -er '.preflight_digest' "$APPROVAL_FILE")"
approved_capacity_probe_digest="$(jq -er '.capacity_probe_digest' "$APPROVAL_FILE")"
approval_reference="$(jq -er '.approval_reference' "$APPROVAL_FILE")"
if ! jq -e '.key_vault_policy_exclusion_approved == true' \
  "$APPROVAL_FILE" >/dev/null; then
  echo "Approval must explicitly authorize the temporary Key Vault policy exclusion" >&2
  exit 11
fi
[[ "$approved_digest" == "$plan_digest" ]] || {
  echo "Approved digest does not match the exact saved plan" >&2
  exit 11
}
[[ "$approved_preflight_digest" == "$preflight_digest" ]] || {
  echo "Approved preflight digest does not match the supplied preflight evidence" >&2
  exit 11
}
[[ "$approved_capacity_probe_digest" == "$capacity_probe_digest" ]] || {
  echo "Approved capacity-probe digest does not match the supplied probe evidence" >&2
  exit 11
}

preflight_assessed_at="$(jq -er '.capacity.assessed_at' "$PREFLIGHT_RESULTS_FILE")"
preflight_age="$(($(date -u +%s) - $(date -u -d "$preflight_assessed_at" +%s)))"
(( preflight_age >= 0 && preflight_age <= ${PREFLIGHT_MAX_AGE_SECONDS:-3600} )) || {
  echo "Preflight evidence is stale or has a future timestamp" >&2
  exit 11
}

start_epoch="$(date +%s)"
terraform -chdir=terraform apply -input=false "$PLAN_FILE"
elapsed_minutes="$(( ($(date +%s) - start_epoch + 59) / 60 ))"
(( elapsed_minutes <= 90 )) || {
  echo "Provisioning exceeded the 90-minute acceptance target" >&2
  exit 12
}

terraform -chdir=terraform output -json inventory |
  jq --arg digest "$plan_digest" --arg approval "$approval_reference" \
    --arg preflight_digest "$preflight_digest" \
    --arg capacity_probe_digest "$capacity_probe_digest" \
    --slurpfile preflight "$PREFLIGHT_RESULTS_FILE" \
    --slurpfile probe "$CAPACITY_PROBE_RESULTS_FILE" \
    'if $preflight[0].images.compatibility.status != "validated" then
       error("Preflight image compatibility was not validated")
     elif $preflight[0].capacity.status != "validated" then
       error("Preflight quota and zonal capacity were not validated")
     elif $probe[0].allocation_state != "allocated" or $probe[0].cleanup_state != "verified" then
       error("Capacity probe allocation and cleanup were not verified")
     elif .versions.scheduler_image != $preflight[0].images.scheduler.urn then
       error("Scheduler image differs from preflight evidence")
     elif .versions.burst_compute_image != $preflight[0].images.burst_compute.urn then
       error("Burst-compute image differs from preflight evidence")
     elif .burst_region != $probe[0].region or .burst_zone != $probe[0].zone then
       error("Capacity-probe placement differs from Terraform inventory")
     elif .versions.burst_compute_image != $probe[0].image_urn then
       error("Capacity-probe image differs from Terraform inventory")
     else
       .image_compatibility = $preflight[0].images.compatibility |
       .capacity_assessment = $preflight[0].capacity |
       .capacity_probe = $probe[0] |
       .validation.plan_digest = $digest |
       .validation.preflight_digest = $preflight_digest |
       .validation.capacity_probe_digest = $capacity_probe_digest |
       .validation.approval_reference = $approval
     end' \
    >"$EVIDENCE_DIR/inventory.json"

jq -n \
  --arg plan_digest "$plan_digest" \
  --arg preflight_digest "$preflight_digest" \
  --arg capacity_probe_digest "$capacity_probe_digest" \
  --arg approval_reference "$approval_reference" \
  --argjson elapsed_minutes "$elapsed_minutes" \
  '{status: "terraform_foundation_only", acceptance_complete: false,
    plan_digest: $plan_digest, preflight_digest: $preflight_digest,
    capacity_probe_digest:$capacity_probe_digest,
    approval_reference: $approval_reference,
    key_vault_policy_exclusion_approved: true,
    elapsed_minutes: $elapsed_minutes}' \
  >"$EVIDENCE_DIR/provisioning.json"
