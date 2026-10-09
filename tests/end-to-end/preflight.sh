#!/usr/bin/env bash
set -euo pipefail

for command in az jq terraform timeout; do
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
: "${BURST_COMPUTE_URN:?BURST_COMPUTE_URN is required}"
: "${WINDOWS_URN:?WINDOWS_URN is required}"

if [[ "${SOURCE_REGION,,}" == "${BURST_REGION,,}" ]]; then
  echo "Source and burst regions must differ" >&2
  exit 3
fi

az_timeout_seconds="${AZ_COMMAND_TIMEOUT_SECONDS:-120}"
declare -A sku_data=()
declare -A image_data=()

progress() {
  printf '[preflight] %s\n' "$*" >&2
}

run_az() {
  local status
  timeout --foreground "${az_timeout_seconds}s" az "$@" && return
  status="$?"
  if [[ "$status" -eq 124 ]]; then
    echo "Azure CLI command timed out after ${az_timeout_seconds}s: az $*" >&2
  fi
  return "$status"
}

load_sku() {
  local region="$1" size="$2"
  local key="$region|$size"
  if [[ ! -v "sku_data[$key]" ]]; then
    progress "Querying VM size $size in $region"
    sku_data["$key"]="$(run_az vm list-skus --location "$region" --size "$size" --all \
      --query "[?name=='$size'] | [0]" --output json)"
  fi
}

load_image() {
  local region="$1" urn="$2"
  local key="$region|$urn"
  local publisher offer sku version
  if [[ ! -v "image_data[$key]" ]]; then
    IFS=: read -r publisher offer sku version <<<"$urn"
    progress "Querying image $urn in $region"
    image_data["$key"]="$(run_az vm image show --location "$region" \
      --publisher "$publisher" --offer "$offer" --sku "$sku" --version "$version" \
      --output json)"
  fi
}

progress "Checking subscription and regions"
subscription_id="$(run_az account show --query id --output tsv)"
locations="$(run_az account list-locations --query '[].name' --output tsv)"
grep -Fxq "$SOURCE_REGION" <<<"$locations" || { echo "Unsupported source region: $SOURCE_REGION" >&2; exit 4; }
grep -Fxq "$BURST_REGION" <<<"$locations" || { echo "Unsupported burst region: $BURST_REGION" >&2; exit 4; }

check_sku() {
  local region="$1" size="$2"
  local restrictions
  load_sku "$region" "$size"
  jq -e --arg size "$size" '.name == $size' <<<"${sku_data["$region|$size"]}" >/dev/null || {
    echo "VM size $size is unavailable in $region" >&2
    return 1
  }
  restrictions="$(jq -r '.restrictions[]?.reasonCode' <<<"${sku_data["$region|$size"]}")"
  if [[ -n "$restrictions" ]]; then
    echo "VM size $size is restricted in $region: $restrictions" >&2
    return 1
  fi
}

check_image() {
  local region="$1" urn="$2"
  IFS=: read -r publisher offer sku version <<<"$urn"
  [[ -n "$publisher" && -n "$offer" && -n "$sku" && -n "$version" ]] || {
    echo "Image URN is incomplete: $urn" >&2
    return 1
  }
  load_image "$region" "$urn"
}

image_property() {
  local region="$1" urn="$2" property="$3"
  load_image "$region" "$urn"
  jq -er --arg property "$property" '.[$property]' <<<"${image_data["$region|$urn"]}"
}

size_capability() {
  local region="$1" size="$2" capability="$3"
  load_sku "$region" "$size"
  jq -er --arg capability "$capability" \
    '.capabilities[] | select(.name == $capability) | .value' \
    <<<"${sku_data["$region|$size"]}"
}

check_image_size_compatibility() {
  local role="$1" region="$2" urn="$3" size="$4"
  local image_generation image_architecture size_generations size_architecture
  image_generation="$(image_property "$region" "$urn" hyperVGeneration)"
  image_architecture="$(image_property "$region" "$urn" architecture)"
  size_generations="$(size_capability "$region" "$size" HyperVGenerations)"
  size_architecture="$(size_capability "$region" "$size" CpuArchitectureType)"

  [[ -n "$image_generation" && -n "$size_generations" &&
    ",${size_generations^^}," == *",${image_generation^^},"* ]] || {
    echo "$role image Hyper-V generation $image_generation is incompatible with $size ($size_generations)" >&2
    return 1
  }
  [[ -n "$image_architecture" && -n "$size_architecture" &&
    "${image_architecture,,}" == "${size_architecture,,}" ]] || {
    echo "$role image architecture $image_architecture is incompatible with $size ($size_architecture)" >&2
    return 1
  }
}

image_family_major() {
  local urn="$1"
  local publisher offer sku version
  IFS=: read -r publisher offer sku version <<<"$urn"
  [[ "${publisher,,}" == "almalinux" && "$sku" =~ ^([0-9]+)(-|_) ]] || {
    echo "Image must identify a supported AlmaLinux major release: $urn" >&2
    return 1
  }
  printf '%s:%s\n' "${publisher,,}" "${BASH_REMATCH[1]}"
}

check_sku "$SOURCE_REGION" "$CYCLECLOUD_VM_SIZE"
check_sku "$SOURCE_REGION" "$SCHEDULER_VM_SIZE"
check_sku "$SOURCE_REGION" "$WINDOWS_VM_SIZE"
check_sku "$BURST_REGION" "$BURST_VM_SIZE"
check_image "$SOURCE_REGION" "$CYCLECLOUD_URN"
check_image "$SOURCE_REGION" "$SCHEDULER_URN"
check_image "$SOURCE_REGION" "$WINDOWS_URN"
check_image "$BURST_REGION" "$BURST_COMPUTE_URN"
check_image_size_compatibility scheduler "$SOURCE_REGION" "$SCHEDULER_URN" "$SCHEDULER_VM_SIZE"
check_image_size_compatibility burst-compute "$BURST_REGION" "$BURST_COMPUTE_URN" "$BURST_VM_SIZE"

scheduler_family_major="$(image_family_major "$SCHEDULER_URN")"
burst_family_major="$(image_family_major "$BURST_COMPUTE_URN")"
[[ "$scheduler_family_major" == "$burst_family_major" ]] || {
  echo "Scheduler and burst-compute images must use the same operating-system major release" >&2
  exit 6
}
IFS=: read -r image_family image_major <<<"$scheduler_family_major"
scheduler_generation="$(image_property "$SOURCE_REGION" "$SCHEDULER_URN" hyperVGeneration)"
scheduler_architecture="$(image_property "$SOURCE_REGION" "$SCHEDULER_URN" architecture)"

progress "Checking CycleCloud Marketplace terms"
run_az vm image terms show --urn "$CYCLECLOUD_URN" \
  --query "accepted == true" --output tsv | grep -qi '^true$' || {
  echo "CycleCloud Marketplace terms are not accepted for $CYCLECLOUD_URN" >&2
  exit 5
}

progress "All preflight checks passed"
jq -n \
  --arg subscription_id "$subscription_id" \
  --arg source_region "$SOURCE_REGION" \
  --arg burst_region "$BURST_REGION" \
  --arg cyclecloud_version "8.9.3" \
  --arg burst_vm_size "$BURST_VM_SIZE" \
  --arg scheduler_urn "$SCHEDULER_URN" \
  --arg burst_compute_urn "$BURST_COMPUTE_URN" \
  --arg image_family "$image_family" \
  --arg image_major "$image_major" \
  --arg image_generation "$scheduler_generation" \
  --arg image_architecture "$scheduler_architecture" \
  '{
    subscription_id: $subscription_id,
    source_region: $source_region,
    burst_region: $burst_region,
    cyclecloud_version: $cyclecloud_version,
    burst_vm_size: $burst_vm_size,
    images: {
      scheduler: {urn: $scheduler_urn},
      burst_compute: {urn: $burst_compute_urn},
      compatibility: {
        status: "validated",
        os_family: $image_family,
        os_major: $image_major,
        hyperv_generation: $image_generation,
        architecture: $image_architecture
      }
    },
    global_peering: "validated during reviewed Terraform plan",
    capacity: "SKU available and unrestricted; allocation remains subject to Azure at apply"
  }'
