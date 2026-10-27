#!/usr/bin/env bash
set -euo pipefail
umask 077

for command in az jq sha256sum terraform; do
  command -v "$command" >/dev/null || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 2
  }
done

mode="${1:-}"
case "$mode" in
  prepare|what-if|apply|reconcile|rbac-apply|rbac-remove-apply|identity-receipt|cleanup-plan|cleanup) ;;
  *)
    echo "Usage: $0 {prepare|what-if|apply|reconcile|rbac-apply|rbac-remove-apply|identity-receipt|cleanup-plan|cleanup}" >&2
    exit 2
    ;;
esac

: "${CYCLECLOUD_TEMPLATE_FILE:?CYCLECLOUD_TEMPLATE_FILE is required}"
: "${CYCLECLOUD_PARAMETERS_FILE:?CYCLECLOUD_PARAMETERS_FILE is required}"
: "${CYCLECLOUD_WHAT_IF_FILE:?CYCLECLOUD_WHAT_IF_FILE is required}"
: "${CYCLECLOUD_APPROVAL_FILE:?CYCLECLOUD_APPROVAL_FILE is required}"
: "${CYCLECLOUD_EVIDENCE_DIR:?CYCLECLOUD_EVIDENCE_DIR is required}"
: "${CYCLECLOUD_CLEANUP_PLAN_FILE:?CYCLECLOUD_CLEANUP_PLAN_FILE is required}"
: "${CYCLECLOUD_CLEANUP_APPROVAL_FILE:?CYCLECLOUD_CLEANUP_APPROVAL_FILE is required}"

source_template="infra/cyclecloud/main.bicep"
mkdir -p "$CYCLECLOUD_EVIDENCE_DIR"

digest() {
  sha256sum "$1" | awk '{print $1}'
}

deployment_values() {
  terraform -chdir=terraform output -json cyclecloud_deployment
}

stack_coordinates() {
  local values
  values="$(deployment_values)"
  resource_group_name="$(jq -er '.resource_group_name' <<<"$values")"
  stack_name="$(jq -er '.vm_name + "-stack"' <<<"$values")"
  subscription_id="$(az account show --query id --output tsv)"
}

verify_approval() {
  local approved_template approved_parameters approved_what_if
  approved_template="$(jq -er '.template_digest' "$CYCLECLOUD_APPROVAL_FILE")"
  approved_parameters="$(jq -er '.parameters_digest' "$CYCLECLOUD_APPROVAL_FILE")"
  approved_what_if="$(jq -er '.what_if_digest' "$CYCLECLOUD_APPROVAL_FILE")"
  jq -er '.approval_reference | strings | select(length > 0)' \
    "$CYCLECLOUD_APPROVAL_FILE" >/dev/null

  [[ "$approved_template" == "$(digest "$CYCLECLOUD_TEMPLATE_FILE")" ]] || {
    echo "Approved CycleCloud template digest does not match" >&2
    exit 11
  }
  [[ "$approved_parameters" == "$(digest "$CYCLECLOUD_PARAMETERS_FILE")" ]] || {
    echo "Approved CycleCloud parameters digest does not match" >&2
    exit 11
  }
  [[ "$approved_what_if" == "$(digest "$CYCLECLOUD_WHAT_IF_FILE")" ]] || {
    echo "Approved CycleCloud what-if digest does not match" >&2
    exit 11
  }
}

verify_plan_approval() {
  local plan_file="$1"
  local approval_file="$2"
  local expected_phase="$3"
  [[ -f "$plan_file" && -f "$approval_file" ]] || {
    echo "CycleCloud RBAC plan or approval file does not exist" >&2
    exit 10
  }
  [[ "$(jq -er '.plan_digest' "$approval_file")" == "$(digest "$plan_file")" ]] || {
    echo "Approved CycleCloud RBAC plan digest does not match" >&2
    exit 11
  }
  [[ "$(jq -er '.identity_phase' "$approval_file")" == "$expected_phase" ]] || {
    echo "Approved CycleCloud identity phase does not match" >&2
    exit 11
  }
  jq -er '.approval_reference | strings | select(length > 0)' "$approval_file" >/dev/null
}

verify_entra_p1_receipt() {
  local receipt_file="$1"
  [[ -f "$receipt_file" ]] || {
    echo "Microsoft Entra ID P1 receipt does not exist" >&2
    exit 10
  }
  jq -e '
    .result == "passed" and
    .detailCode == "entra_p1_verified"
  ' "$receipt_file" >/dev/null || {
    echo "Accepted Microsoft Entra ID P1 receipt is required" >&2
    exit 12
  }
}

case "$mode" in
  prepare)
    : "${CYCLECLOUD_SSH_PUBLIC_KEY_FILE:?CYCLECLOUD_SSH_PUBLIC_KEY_FILE is required}"
    [[ -f "$CYCLECLOUD_SSH_PUBLIC_KEY_FILE" ]] || {
      echo "CycleCloud SSH public key file does not exist" >&2
      exit 2
    }
    values="$(deployment_values)"
    az bicep build --file "$source_template" --outfile "$CYCLECLOUD_TEMPLATE_FILE"
    jq -n \
      --arg location "$(jq -er '.location' <<<"$values")" \
      --arg vm_name "$(jq -er '.vm_name' <<<"$values")" \
      --arg vm_size "$(jq -er '.vm_size' <<<"$values")" \
      --arg zone "$(jq -er '.zone' <<<"$values")" \
      --arg nic_resource_id "$(jq -er '.nic_resource_id' <<<"$values")" \
      --arg custom_data "$(jq -er '.custom_data' <<<"$values")" \
      --arg chef_payload_base64 "$(jq -er '.chef_payload_base64' <<<"$values")" \
      --arg chef_manifest_base64 "$(jq -er '.chef_manifest_base64' <<<"$values")" \
      --arg chef_node_specification_base64 "$(jq -er '.chef_node_specification_base64' <<<"$values")" \
      --arg chef_policy_lock_base64 "$(jq -er '.chef_policy_lock_base64' <<<"$values")" \
      --arg chef_payload_sha256 "$(jq -er '.chef_payload_sha256' <<<"$values")" \
      --arg chef_manifest_sha256 "$(jq -er '.chef_manifest_sha256' <<<"$values")" \
      --arg chef_node_specification_sha256 "$(jq -er '.chef_node_specification_sha256' <<<"$values")" \
      --arg chef_policy_lock_sha256 "$(jq -er '.chef_policy_lock_sha256' <<<"$values")" \
      --argjson chef_decoded_size_bytes "$(jq -er '.chef_decoded_size_bytes' <<<"$values")" \
      --arg admin_ssh_public_key "$(tr -d '\r\n' <"$CYCLECLOUD_SSH_PUBLIC_KEY_FILE")" \
      --arg image_publisher "$(jq -er '.image.publisher' <<<"$values")" \
      --arg image_offer "$(jq -er '.image.offer' <<<"$values")" \
      --arg image_sku "$(jq -er '.image.sku' <<<"$values")" \
      --arg image_version "$(jq -er '.image.version' <<<"$values")" \
      --arg plan_name "$(jq -er '.image.plan_name' <<<"$values")" \
      --arg plan_product "$(jq -er '.image.product' <<<"$values")" \
      --argjson tags "$(jq -c '.tags' <<<"$values")" \
      '{
        "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
        contentVersion: "1.0.0.0",
        parameters: {
          location: {value: $location},
          vmName: {value: $vm_name},
          vmSize: {value: $vm_size},
          zone: {value: $zone},
          nicResourceId: {value: $nic_resource_id},
          customData: {value: $custom_data},
          chefPayloadBase64: {value: $chef_payload_base64},
          chefManifestBase64: {value: $chef_manifest_base64},
          chefNodeSpecificationBase64: {value: $chef_node_specification_base64},
          chefPolicyLockBase64: {value: $chef_policy_lock_base64},
          chefPayloadSha256: {value: $chef_payload_sha256},
          chefManifestSha256: {value: $chef_manifest_sha256},
          chefNodeSpecificationSha256: {value: $chef_node_specification_sha256},
          chefPolicyLockSha256: {value: $chef_policy_lock_sha256},
          chefDecodedSizeBytes: {value: $chef_decoded_size_bytes},
          adminSshPublicKey: {value: $admin_ssh_public_key},
          imagePublisher: {value: $image_publisher},
          imageOffer: {value: $image_offer},
          imageSku: {value: $image_sku},
          imageVersion: {value: $image_version},
          planName: {value: $plan_name},
          planProduct: {value: $plan_product},
          tags: {value: $tags}
        }
      }' >"$CYCLECLOUD_PARAMETERS_FILE"
    printf '%s  %s\n' "$(digest "$CYCLECLOUD_TEMPLATE_FILE")" "$CYCLECLOUD_TEMPLATE_FILE"
    printf '%s  %s\n' "$(digest "$CYCLECLOUD_PARAMETERS_FILE")" "$CYCLECLOUD_PARAMETERS_FILE"
    ;;
  what-if|reconcile)
    stack_coordinates
    az deployment group validate \
      --subscription "$subscription_id" \
      --resource-group "$resource_group_name" \
      --template-file "$CYCLECLOUD_TEMPLATE_FILE" \
      --parameters "@$CYCLECLOUD_PARAMETERS_FILE" \
      --output none
    az deployment group what-if \
      --subscription "$subscription_id" \
      --resource-group "$resource_group_name" \
      --template-file "$CYCLECLOUD_TEMPLATE_FILE" \
      --parameters "@$CYCLECLOUD_PARAMETERS_FILE" \
      --no-pretty-print \
      --result-format FullResourcePayloads \
      --output json |
      jq -S . >"$CYCLECLOUD_WHAT_IF_FILE"
    jq -e --arg mode "$mode" '
      [.changes[] | select(.changeType != "Ignore")] as $actionable |
      all($actionable[];
        .resourceId | ascii_downcase |
        contains("/providers/microsoft.compute/virtualmachines/")
      ) and
      (
        $mode == "reconcile" or
        (
          ($actionable | length) == 1 and
          $actionable[0].changeType == "Create"
        )
      )
    ' "$CYCLECLOUD_WHAT_IF_FILE" >/dev/null
    printf '%s  %s\n' "$(digest "$CYCLECLOUD_WHAT_IF_FILE")" "$CYCLECLOUD_WHAT_IF_FILE"
    ;;
  apply)
    [[ -f "$CYCLECLOUD_APPROVAL_FILE" ]] || {
      echo "CycleCloud approval file does not exist" >&2
      exit 10
    }
    verify_approval
    stack_coordinates
    az stack group create \
      --subscription "$subscription_id" \
      --resource-group "$resource_group_name" \
      --name "$stack_name" \
      --template-file "$CYCLECLOUD_TEMPLATE_FILE" \
      --parameters "@$CYCLECLOUD_PARAMETERS_FILE" \
      --action-on-unmanage deleteAll \
      --deny-settings-mode none \
      --description "Pinned CycleCloud Marketplace VM-only deployment" \
      --output json |
      jq -S . >"$CYCLECLOUD_EVIDENCE_DIR/deployment-stack.json"
    vm_json="$(
      az vm show \
      --subscription "$subscription_id" \
      --resource-group "$resource_group_name" \
      --name "${stack_name%-stack}" \
      --output json
    )"
    jq -e '
      .identity.type == "SystemAssigned" and
      ((.identity.userAssignedIdentities // {}) | length) == 0 and
      (.identity.principalId | strings | length) > 0
    ' <<<"$vm_json" >/dev/null || {
      echo "CycleCloud VM does not have the approved system-identity-only shape" >&2
      exit 12
    }
    jq -S 'del(.identity.tenantId)' <<<"$vm_json" \
      >"$CYCLECLOUD_EVIDENCE_DIR/virtual-machine.json"
    ;;
  rbac-apply|rbac-remove-apply)
    : "${CYCLECLOUD_RBAC_PLAN_FILE:?CYCLECLOUD_RBAC_PLAN_FILE is required}"
    : "${CYCLECLOUD_RBAC_APPROVAL_FILE:?CYCLECLOUD_RBAC_APPROVAL_FILE is required}"
    if [[ "$mode" == "rbac-apply" ]]; then
      : "${CYCLECLOUD_ENTRA_P1_RECEIPT_FILE:?CYCLECLOUD_ENTRA_P1_RECEIPT_FILE is required}"
      verify_entra_p1_receipt "$CYCLECLOUD_ENTRA_P1_RECEIPT_FILE"
      expected_phase=post-create-rbac
    else
      expected_phase=foundation
    fi
    verify_plan_approval \
      "$CYCLECLOUD_RBAC_PLAN_FILE" \
      "$CYCLECLOUD_RBAC_APPROVAL_FILE" \
      "$expected_phase"
    if [[ "$mode" == "rbac-apply" ]]; then
      [[ "$(jq -er '.entra_p1_receipt_digest' "$CYCLECLOUD_RBAC_APPROVAL_FILE")" == \
        "$(digest "$CYCLECLOUD_ENTRA_P1_RECEIPT_FILE")" ]] || {
        echo "Approved Microsoft Entra ID P1 receipt digest does not match" >&2
        exit 11
      }
    fi
    terraform -chdir=terraform apply \
      -input=false \
      -no-color \
      "$CYCLECLOUD_RBAC_PLAN_FILE"
    actual_phase="$(
      terraform -chdir=terraform output -json cyclecloud_identity_rbac |
        jq -er '.phase'
    )"
    [[ "$actual_phase" == "$expected_phase" ]] || {
      echo "Applied CycleCloud identity phase does not match approval" >&2
      exit 12
    }
    ;;
  identity-receipt)
    : "${CYCLECLOUD_IDENTITY_RECEIPT_FILE:?CYCLECLOUD_IDENTITY_RECEIPT_FILE is required}"
    : "${CYCLECLOUD_ENTRA_P1_RECEIPT_FILE:?CYCLECLOUD_ENTRA_P1_RECEIPT_FILE is required}"
    verify_entra_p1_receipt "$CYCLECLOUD_ENTRA_P1_RECEIPT_FILE"
    stack_coordinates
    vm_json="$(
      az vm show \
        --subscription "$subscription_id" \
        --resource-group "$resource_group_name" \
        --name "${stack_name%-stack}" \
        --output json
    )"
    rbac_json="$(terraform -chdir=terraform output -json cyclecloud_identity_rbac)"
    deployment_json="$(deployment_values)"
    capability_message="$(
      # shellcheck disable=SC2016
      az vm run-command invoke \
        --subscription "$subscription_id" \
        --resource-group "$resource_group_name" \
        --name "${stack_name%-stack}" \
        --command-id RunShellScript \
        --scripts 'printf "IDENTITY_CAPABILITIES_BASE64=%s\n" "$(base64 -w0 /var/lib/cyclecloud-first-run/identity-capabilities.json)"' \
        --query 'value[0].message' \
        --output tsv
    )"
    capability_base64="$(
      grep -Eo 'IDENTITY_CAPABILITIES_BASE64=[A-Za-z0-9+/=]+' <<<"$capability_message" |
        tail -n 1 |
        cut -d= -f2-
    )"
    [[ -n "$capability_base64" ]] || {
      echo "CycleCloud identity capability receipt is missing" >&2
      exit 12
    }
    capability_json="$(base64 --decode <<<"$capability_base64")"
    jq -n \
      --arg source_revision "$(jq -er '.source_revision' <<<"$deployment_json")" \
      --arg vm_resource_id "$(jq -er '.id' <<<"$vm_json")" \
      --arg principal_id "$(jq -er '.identity.principalId' <<<"$vm_json")" \
      --arg identity_type "$(jq -er '.identity.type' <<<"$vm_json")" \
      --argjson user_assigned_identity_count "$(jq '(.identity.userAssignedIdentities // {}) | length' <<<"$vm_json")" \
      --arg custom_role_definition_id "$(jq -er '.custom_role_definition_id' <<<"$rbac_json")" \
      --arg custom_role_definition_digest "$(jq -er '.custom_role_definition_digest' <<<"$rbac_json")" \
      --arg custom_role_assignment_scope "$(jq -er '.custom_role_assignment_scope' <<<"$rbac_json")" \
      --arg key_vault_role_assignment_scope "$(jq -er '.key_vault_assignment_scope' <<<"$rbac_json")" \
      --arg locker_identity_resource_id "$(jq -er '.locker_identity_resource_id' <<<"$rbac_json")" \
      --arg locker_role "$(jq -er '.locker_role' <<<"$rbac_json")" \
      --arg locker_role_assignment_scope "$(jq -er '.locker_assignment_scope' <<<"$rbac_json")" \
      --argjson capabilities "$capability_json" \
      '{
        schemaVersion: 1,
        sourceRevision: $source_revision,
        vmResourceId: $vm_resource_id,
        principalId: $principal_id,
        identityType: $identity_type,
        userAssignedIdentityCount: $user_assigned_identity_count,
        customRoleDefinitionId: $custom_role_definition_id,
        customRoleDefinitionDigest: $custom_role_definition_digest,
        customRoleAssignmentScope: $custom_role_assignment_scope,
        keyVaultRoleAssignmentScope: $key_vault_role_assignment_scope,
        lockerIdentityResourceId: $locker_identity_resource_id,
        lockerRole: $locker_role,
        lockerRoleAssignmentScope: $locker_role_assignment_scope,
        entraP1Verified: true,
        managementAccessVerified: $capabilities.managementAccessVerified,
        userDelegationVerified: $capabilities.userDelegationVerified,
        secretReadVerified: $capabilities.secretReadVerified,
        checkedAt: $capabilities.checkedAt,
        result: "passed",
        detailCode: "cyclecloud_identity_rbac_ready"
      }' >"$CYCLECLOUD_IDENTITY_RECEIPT_FILE"
    python3 - "$CYCLECLOUD_IDENTITY_RECEIPT_FILE" <<'PY'
import json
from pathlib import Path
import sys

from jsonschema import Draft202012Validator, FormatChecker

root = Path.cwd()
schema = json.loads(
    (root / "specs/005-automated-chef-bootstrap/contracts/cyclecloud-identity-rbac.schema.json").read_text()
)
document = json.loads(Path(sys.argv[1]).read_text())
Draft202012Validator(schema, format_checker=FormatChecker()).validate(document)
PY
    ;;
  cleanup-plan)
    stack_coordinates
    az stack group show \
      --subscription "$subscription_id" \
      --resource-group "$resource_group_name" \
      --name "$stack_name" \
      --output json |
      jq -S . >"$CYCLECLOUD_CLEANUP_PLAN_FILE"
    printf '%s  %s\n' \
      "$(digest "$CYCLECLOUD_CLEANUP_PLAN_FILE")" \
      "$CYCLECLOUD_CLEANUP_PLAN_FILE"
    ;;
  cleanup)
    [[ -f "$CYCLECLOUD_CLEANUP_APPROVAL_FILE" ]] || {
      echo "CycleCloud cleanup approval file does not exist" >&2
      exit 10
    }
    approved_cleanup_digest="$(
      jq -er '.stack_snapshot_digest' "$CYCLECLOUD_CLEANUP_APPROVAL_FILE"
    )"
    jq -er '.approval_reference | strings | select(length > 0)' \
      "$CYCLECLOUD_CLEANUP_APPROVAL_FILE" >/dev/null
    [[ "$approved_cleanup_digest" == "$(digest "$CYCLECLOUD_CLEANUP_PLAN_FILE")" ]] || {
      echo "Approved CycleCloud cleanup digest does not match" >&2
      exit 11
    }
    stack_coordinates
    vm_identity="$(
      az vm show \
        --subscription "$subscription_id" \
        --resource-group "$resource_group_name" \
        --name "${stack_name%-stack}" \
        --query identity \
        --output json
    )"
    if [[ "$(jq -r '.type' <<<"$vm_identity")" == "SystemAssigned" ]]; then
      rbac_json="$(terraform -chdir=terraform output -json cyclecloud_identity_rbac)"
      jq -e '
        .phase == "foundation" and
        .post_create_rbac_enabled == false and
        .system_principal_id == null
      ' <<<"$rbac_json" >/dev/null || {
        echo "CycleCloud system-principal assignments must be removed before stack cleanup" >&2
        exit 12
      }
      principal_id="$(jq -er '.principalId' <<<"$vm_identity")"
      custom_role_count="$(
        az role assignment list \
          --subscription "$subscription_id" \
          --assignee-object-id "$principal_id" \
          --scope "$(jq -er '.custom_role_assignment_scope' <<<"$rbac_json")" \
          --query "[?roleDefinitionId=='$(jq -er '.custom_role_definition_id' <<<"$rbac_json")'] | length(@)" \
          --output tsv
      )"
      vault_role_count="$(
        az role assignment list \
          --subscription "$subscription_id" \
          --assignee-object-id "$principal_id" \
          --scope "$(jq -er '.key_vault_assignment_scope' <<<"$rbac_json")" \
          --query "[?roleDefinitionName=='Key Vault Secrets User'] | length(@)" \
          --output tsv
      )"
      [[ "$custom_role_count" == "0" && "$vault_role_count" == "0" ]] || {
        echo "CycleCloud system-principal role assignments still exist" >&2
        exit 12
      }
    fi
    az stack group delete \
      --subscription "$subscription_id" \
      --resource-group "$resource_group_name" \
      --name "$stack_name" \
      --action-on-unmanage deleteAll \
      --resources-without-delete-support fail \
      --yes
    if az vm show \
      --subscription "$subscription_id" \
      --resource-group "$resource_group_name" \
      --name "${stack_name%-stack}" \
      --output none 2>/dev/null; then
      echo "CycleCloud VM still exists after stack cleanup" >&2
      exit 12
    fi
    ;;
esac
