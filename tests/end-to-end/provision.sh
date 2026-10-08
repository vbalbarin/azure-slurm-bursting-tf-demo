#!/usr/bin/env bash
set -euo pipefail
umask 077

for command in terraform sha256sum jq; do
  command -v "$command" >/dev/null || { echo "Missing required command: $command" >&2; exit 2; }
done

: "${TFVARS_FILE:?TFVARS_FILE is required}"
: "${PLAN_FILE:?PLAN_FILE is required}"
: "${APPROVAL_FILE:?APPROVAL_FILE is required}"
: "${EVIDENCE_DIR:?EVIDENCE_DIR is required}"

[[ -f "$TFVARS_FILE" ]] || { echo "TFVARS_FILE does not exist" >&2; exit 2; }
[[ "$PLAN_FILE" != *.tfvars* ]] || { echo "PLAN_FILE must not be a variable file" >&2; exit 2; }
mkdir -p "$EVIDENCE_DIR"

terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform validate
terraform -chdir=terraform plan -input=false -var-file="$TFVARS_FILE" -out="$PLAN_FILE"

plan_digest="$(sha256sum "$PLAN_FILE" | awk '{print $1}')"
printf '%s\n' "$plan_digest" >"$EVIDENCE_DIR/plan.sha256"
terraform -chdir=terraform show -json "$PLAN_FILE" >"$EVIDENCE_DIR/plan.json"

if [[ ! -f "$APPROVAL_FILE" ]]; then
  echo "Plan created with digest $plan_digest; approval is required before apply" >&2
  exit 10
fi

approved_digest="$(jq -er '.plan_digest' "$APPROVAL_FILE")"
approval_reference="$(jq -er '.approval_reference' "$APPROVAL_FILE")"
[[ "$approved_digest" == "$plan_digest" ]] || {
  echo "Approved digest does not match the exact saved plan" >&2
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
    '.validation.plan_digest = $digest | .validation.approval_reference = $approval' \
    >"$EVIDENCE_DIR/inventory.json"

jq -n \
  --arg plan_digest "$plan_digest" \
  --arg approval_reference "$approval_reference" \
  --argjson elapsed_minutes "$elapsed_minutes" \
  '{plan_digest: $plan_digest, approval_reference: $approval_reference, elapsed_minutes: $elapsed_minutes}' \
  >"$EVIDENCE_DIR/provisioning.json"
