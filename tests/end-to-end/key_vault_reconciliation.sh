#!/usr/bin/env bash
set -euo pipefail
umask 077

case "${1:-}" in
  check|plan|apply) action="$1" ;;
  *)
    echo "Usage: $0 {check|plan|apply}" >&2
    exit 2
    ;;
esac

for command in az jq sha256sum terraform; do
  command -v "$command" >/dev/null || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 2
  }
done

: "${TFVARS_FILE:?TFVARS_FILE is required}"
: "${FOUNDATION_PLAN_FILE:?FOUNDATION_PLAN_FILE is required}"
: "${KEY_VAULT_RECONCILIATION_PLAN_FILE:?KEY_VAULT_RECONCILIATION_PLAN_FILE is required}"
: "${KEY_VAULT_RECONCILIATION_APPROVAL_FILE:?KEY_VAULT_RECONCILIATION_APPROVAL_FILE is required}"
: "${KEY_VAULT_PROVISIONING_EVIDENCE_FILE:?KEY_VAULT_PROVISIONING_EVIDENCE_FILE is required}"

key_vault_address="module.key_vault.azurerm_key_vault.this"

expected_posture() {
  terraform -chdir=terraform show -json "$FOUNDATION_PLAN_FILE" |
    jq -ce --arg address "$key_vault_address" '
      [.resource_changes[]? | select(.address == $address)] as $vaults |
      if ($vaults | length) != 1 then
        error("Foundation plan must contain exactly one managed Key Vault")
      else
        $vaults[0].change.after |
        {
          vaultName: .name,
          resourceGroupName: .resource_group_name,
          publicNetworkAccess:
            (if .public_network_access_enabled then "Enabled" else "Disabled" end),
          defaultAction: .network_acls[0].default_action,
          ipRules: .network_acls[0].ip_rules,
          securityControl: .tags.SecurityControl
        }
      end |
      if
        .publicNetworkAccess != "Enabled" or
        .defaultAction != "Deny" or
        (.ipRules | length) != 1 or
        (.ipRules[0] | test(
          "^((25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})\\.){3}" +
          "(25[0-5]|2[0-4][0-9]|1?[0-9]{1,2})/32$"
        ) | not) or
        .securityControl != "Ignore"
      then
        error("Foundation plan does not contain the bounded Key Vault provisioning posture")
      else
        .
      end
    '
}

validate_reconciliation_plan() {
  local expected="$1"
  terraform -chdir=terraform show -json "$KEY_VAULT_RECONCILIATION_PLAN_FILE" |
    jq -e --arg address "$key_vault_address" --argjson expected "$expected" '
      [.resource_changes[]? |
        select(.change.actions != ["no-op"])] as $changes |
      ($changes | length) == 1 and
      $changes[0].address == $address and
      $changes[0].change.actions == ["update"] and
      ($changes[0].change.after | {
        vaultName: .name,
        resourceGroupName: .resource_group_name,
        publicNetworkAccess:
          (if .public_network_access_enabled then "Enabled" else "Disabled" end),
        defaultAction: .network_acls[0].default_action,
        ipRules: .network_acls[0].ip_rules,
        securityControl: .tags.SecurityControl
      }) == $expected
    ' >/dev/null || {
      echo "Reconciliation plan must contain only the exact Key Vault provisioning update" >&2
      exit 11
    }
}

check_live_posture() {
  local expected="$1"
  local reconciliation_applied="$2"
  local approval_reference="${3:-}"
  local observed group_security_control status temporary

  observed="$(
    az keyvault show \
      --resource-group "$(jq -r '.resourceGroupName' <<<"$expected")" \
      --name "$(jq -r '.vaultName' <<<"$expected")" \
      --query '{
        publicNetworkAccess:properties.publicNetworkAccess,
        defaultAction:properties.networkAcls.defaultAction,
        ipRules:properties.networkAcls.ipRules[].value,
        securityControl:tags.SecurityControl
      }' \
      --output json
  )"
  group_security_control="$(
    az group show \
      --name "$(jq -r '.resourceGroupName' <<<"$expected")" \
      --query 'tags.SecurityControl' \
      --output tsv
  )"

  if jq -e --argjson expected "$expected" \
    --arg group_security_control "$group_security_control" '
      . == ($expected | del(.vaultName, .resourceGroupName)) and
      $group_security_control != "Ignore"
    ' <<<"$observed" >/dev/null; then
    status="matched"
  else
    status="reconciliation_required"
  fi

  mkdir -p "$(dirname "$KEY_VAULT_PROVISIONING_EVIDENCE_FILE")"
  temporary="$(mktemp "${KEY_VAULT_PROVISIONING_EVIDENCE_FILE}.XXXXXX")"
  jq -n \
    --arg status "$status" \
    --argjson expected "$expected" \
    --argjson observed "$observed" \
    --arg resource_group_security_control "$group_security_control" \
    --argjson reconciliation_applied "$reconciliation_applied" \
    --arg approval_reference "$approval_reference" \
    '{
      status: $status,
      expected: $expected,
      observed: $observed,
      resourceGroupSecurityControl:
        (if $resource_group_security_control == "" then null
         else $resource_group_security_control end),
      reconciliationApplied: $reconciliation_applied,
      approvalReference:
        (if $approval_reference == "" then null else $approval_reference end)
    }' >"$temporary"
  chmod 0600 "$temporary"
  mv "$temporary" "$KEY_VAULT_PROVISIONING_EVIDENCE_FILE"

  if [[ "$status" != "matched" ]]; then
    echo "Recovered Key Vault does not match the approved provisioning posture; reconciliation is required" >&2
    return 20
  fi
}

expected="$(expected_posture)"

case "$action" in
  check)
    check_live_posture "$expected" false
    ;;
  plan)
    [[ -f "$KEY_VAULT_PROVISIONING_EVIDENCE_FILE" ]] || {
      echo "Run the Key Vault provisioning posture check before planning reconciliation" >&2
      exit 10
    }
    jq -e '.status == "reconciliation_required"' \
      "$KEY_VAULT_PROVISIONING_EVIDENCE_FILE" >/dev/null || {
      echo "Reconciliation planning is allowed only after a mismatched live posture" >&2
      exit 10
    }
    terraform -chdir=terraform plan \
      -input=false \
      -var-file="$TFVARS_FILE" \
      -out="$KEY_VAULT_RECONCILIATION_PLAN_FILE"
    chmod 0600 "$KEY_VAULT_RECONCILIATION_PLAN_FILE"
    validate_reconciliation_plan "$expected"
    sha256sum "$KEY_VAULT_RECONCILIATION_PLAN_FILE"
    ;;
  apply)
    [[ -f "$KEY_VAULT_RECONCILIATION_PLAN_FILE" ]] || {
      echo "Key Vault reconciliation plan does not exist" >&2
      exit 10
    }
    [[ -f "$KEY_VAULT_RECONCILIATION_APPROVAL_FILE" ]] || {
      echo "Key Vault reconciliation approval does not exist" >&2
      exit 10
    }
    approved_digest="$(
      jq -er '.plan_digest' "$KEY_VAULT_RECONCILIATION_APPROVAL_FILE"
    )"
    approval_reference="$(
      jq -er '.approval_reference | strings | select(length > 0)' \
        "$KEY_VAULT_RECONCILIATION_APPROVAL_FILE"
    )"
    jq -e '.key_vault_policy_exclusion_approved == true' \
      "$KEY_VAULT_RECONCILIATION_APPROVAL_FILE" >/dev/null || {
      echo "Approval must authorize the temporary Key Vault policy exclusion" >&2
      exit 11
    }
    [[ "$approved_digest" == "$(
      sha256sum "$KEY_VAULT_RECONCILIATION_PLAN_FILE" | awk '{print $1}'
    )" ]] || {
      echo "Approved digest does not match the Key Vault reconciliation plan" >&2
      exit 11
    }
    validate_reconciliation_plan "$expected"
    terraform -chdir=terraform apply \
      -input=false \
      "$KEY_VAULT_RECONCILIATION_PLAN_FILE"
    check_live_posture "$expected" true "$approval_reference"
    ;;
esac
