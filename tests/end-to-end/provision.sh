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
: "${TF_VAR_backend_readiness_file:?TF_VAR_backend_readiness_file is required}"

[[ -f "$TFVARS_FILE" ]] || { echo "TFVARS_FILE does not exist" >&2; exit 2; }
[[ -f "$PREFLIGHT_RESULTS_FILE" ]] || { echo "PREFLIGHT_RESULTS_FILE does not exist" >&2; exit 2; }
[[ -f "$CAPACITY_PROBE_RESULTS_FILE" ]] || { echo "CAPACITY_PROBE_RESULTS_FILE does not exist" >&2; exit 2; }
[[ -f "$TF_VAR_backend_readiness_file" ]] || { echo "Backend readiness evidence does not exist" >&2; exit 2; }
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
approved_key_vault_cidr="$(
  jq -er '.key_vault_provisioning_ipv4_cidr |
    select(test("^([0-9]{1,3}\\.){3}[0-9]{1,3}/32$"))' "$APPROVAL_FILE"
)"
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

if ! terraform -chdir=terraform show -json "$PLAN_FILE" |
  jq -e --arg cidr "$approved_key_vault_cidr" '
    [.resource_changes[]? |
      select(.address == "module.key_vault.azurerm_key_vault.this")] as $vaults |
    ($vaults | length) == 1 and
    (
      $vaults[0].change.actions == ["create"] or
      $vaults[0].change.actions == ["update"]
    ) and
    $vaults[0].change.after.public_network_access_enabled == true and
    $vaults[0].change.after.network_acls[0].default_action == "Deny" and
    $vaults[0].change.after.network_acls[0].ip_rules == [$cidr] and
    $vaults[0].change.after.tags.SecurityControl == "Ignore"
  ' >/dev/null; then
  echo "Reviewed plan does not contain the exact approved Key Vault provisioning window" >&2
  exit 11
fi

preflight_assessed_at="$(jq -er '.capacity.assessed_at' "$PREFLIGHT_RESULTS_FILE")"
preflight_age="$(($(date -u +%s) - $(date -u -d "$preflight_assessed_at" +%s)))"
(( preflight_age >= 0 && preflight_age <= ${PREFLIGHT_MAX_AGE_SECONDS:-3600} )) || {
  echo "Preflight evidence is stale or has a future timestamp" >&2
  exit 11
}

backend_readiness_assessed_at="$(
  jq -er '
    select(.status == "ready" and .failure_class == "none") |
    .assessed_at
  ' "$TF_VAR_backend_readiness_file"
)"
backend_readiness_age="$(
  echo "$(($(date -u +%s) - $(date -u -d "$backend_readiness_assessed_at" +%s)))"
)"
(( backend_readiness_age >= 0 &&
  backend_readiness_age <= ${FOUNDATION_READINESS_MAX_AGE_SECONDS:-1200} )) || {
  echo "Backend readiness lacks the required foundation-apply freshness headroom" >&2
  exit 11
}

start_epoch="$(date +%s)"
terraform -chdir=terraform apply -input=false "$PLAN_FILE"
elapsed_minutes="$(( ($(date +%s) - start_epoch + 59) / 60 ))"
(( elapsed_minutes <= 90 )) || {
  echo "Provisioning exceeded the 90-minute acceptance target" >&2
  exit 12
}

foundation_no_change_log="${FOUNDATION_NO_CHANGE_LOG_FILE:-$(dirname "$PLAN_FILE")/foundation-no-change.log}"
set +e
terraform -chdir=terraform plan \
  -input=false \
  -var-file="$TFVARS_FILE" \
  -detailed-exitcode \
  -no-color >"$foundation_no_change_log" 2>&1
foundation_no_change_status="$?"
set -e
chmod 0600 "$foundation_no_change_log"

jq -n \
  --arg observed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg protected_log_sha256 "$(
    sha256sum "$foundation_no_change_log" |
      awk '{print $1}'
  )" \
  --argjson exit_code "$foundation_no_change_status" \
  '{
    schema_version: "1.0",
    stage: "post_foundation_no_change",
    observed_at: $observed_at,
    exit_code: $exit_code,
    status: (if $exit_code == 0 then "passed" else "failed" end),
    no_changes: ($exit_code == 0),
    protected_log_sha256: $protected_log_sha256
  }' >"$EVIDENCE_DIR/foundation-no-change.json"

if [[ "$foundation_no_change_status" -ne 0 ]]; then
  echo "Post-foundation plan detected drift or failed; secret writes and appliance deployment are blocked" >&2
  exit 13
fi

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
