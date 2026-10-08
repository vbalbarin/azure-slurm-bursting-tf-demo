#!/usr/bin/env bash
set -euo pipefail

for command in az jq terraform; do
  command -v "$command" >/dev/null || { echo "Missing required command: $command" >&2; exit 2; }
done

: "${SOURCE_REGION:?SOURCE_REGION is required}"
: "${BURST_REGION:?BURST_REGION is required}"
: "${CYCLECLOUD_VM_SIZE:?CYCLECLOUD_VM_SIZE is required}"
: "${SCHEDULER_VM_SIZE:?SCHEDULER_VM_SIZE is required}"
: "${WINDOWS_VM_SIZE:?WINDOWS_VM_SIZE is required}"
: "${BURST_VM_SIZE:?BURST_VM_SIZE is required}"
: "${CYCLECLOUD_URN:?CYCLECLOUD_URN is required}"
: "${SCHEDULER_URN:?SCHEDULER_URN is required}"
: "${WINDOWS_URN:?WINDOWS_URN is required}"

if [[ "${SOURCE_REGION,,}" == "${BURST_REGION,,}" ]]; then
  echo "Source and burst regions must differ" >&2
  exit 3
fi

subscription_id="$(az account show --query id --output tsv)"
locations="$(az account list-locations --query '[].name' --output tsv)"
grep -Fxq "$SOURCE_REGION" <<<"$locations" || { echo "Unsupported source region: $SOURCE_REGION" >&2; exit 4; }
grep -Fxq "$BURST_REGION" <<<"$locations" || { echo "Unsupported burst region: $BURST_REGION" >&2; exit 4; }

check_sku() {
  local region="$1" size="$2"
  local restrictions
  restrictions="$(az vm list-skus --location "$region" --size "$size" --all \
    --query "[?name=='$size'].restrictions[].reasonCode" --output tsv)"
  if [[ -n "$restrictions" ]]; then
    echo "VM size $size is restricted in $region: $restrictions" >&2
    return 1
  fi
  az vm list-skus --location "$region" --size "$size" --all \
    --query "[?name=='$size'] | length(@)" --output tsv | grep -qv '^0$'
}

check_image() {
  local region="$1" urn="$2"
  IFS=: read -r publisher offer sku version <<<"$urn"
  az vm image show --location "$region" --publisher "$publisher" --offer "$offer" \
    --sku "$sku" --version "$version" --output none
}

check_sku "$SOURCE_REGION" "$CYCLECLOUD_VM_SIZE"
check_sku "$SOURCE_REGION" "$SCHEDULER_VM_SIZE"
check_sku "$SOURCE_REGION" "$WINDOWS_VM_SIZE"
check_sku "$BURST_REGION" "$BURST_VM_SIZE"
check_image "$SOURCE_REGION" "$CYCLECLOUD_URN"
check_image "$SOURCE_REGION" "$SCHEDULER_URN"
check_image "$SOURCE_REGION" "$WINDOWS_URN"
check_image "$BURST_REGION" "$SCHEDULER_URN"

az vm image terms show --urn "$CYCLECLOUD_URN" \
  --query "accepted == true" --output tsv | grep -qi '^true$' || {
  echo "CycleCloud Marketplace terms are not accepted for $CYCLECLOUD_URN" >&2
  exit 5
}

jq -n \
  --arg subscription_id "$subscription_id" \
  --arg source_region "$SOURCE_REGION" \
  --arg burst_region "$BURST_REGION" \
  --arg cyclecloud_version "8.9.3" \
  --arg burst_vm_size "$BURST_VM_SIZE" \
  '{
    subscription_id: $subscription_id,
    source_region: $source_region,
    burst_region: $burst_region,
    cyclecloud_version: $cyclecloud_version,
    burst_vm_size: $burst_vm_size,
    global_peering: "validated during reviewed Terraform plan",
    capacity: "SKU available and unrestricted; allocation remains subject to Azure at apply"
  }'
