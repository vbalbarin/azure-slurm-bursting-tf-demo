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
  prepare|what-if|apply|reconcile|cleanup-plan|cleanup) ;;
  *)
    echo "Usage: $0 {prepare|what-if|apply|reconcile|cleanup-plan|cleanup}" >&2
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
    az vm show \
      --subscription "$subscription_id" \
      --resource-group "$resource_group_name" \
      --name "${stack_name%-stack}" \
      --output json |
      jq -S 'del(.identity.principalId, .identity.tenantId)' \
        >"$CYCLECLOUD_EVIDENCE_DIR/virtual-machine.json"
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
