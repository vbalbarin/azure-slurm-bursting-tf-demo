#!/usr/bin/env bash
set -euo pipefail

for command in az jq terraform timeout; do
  command -v "$command" >/dev/null || { echo "Missing required command: $command" >&2; exit 2; }
done

: "${SOURCE_REGION:?SOURCE_REGION is required}"
: "${BURST_REGION:?BURST_REGION is required}"
: "${BURST_ZONE:?BURST_ZONE is required}"
: "${CYCLECLOUD_VM_SIZE:?CYCLECLOUD_VM_SIZE is required}"
: "${SCHEDULER_VM_SIZE:?SCHEDULER_VM_SIZE is required}"
: "${WINDOWS_VM_SIZE:?WINDOWS_VM_SIZE is required}"
: "${BURST_VM_SIZE:?BURST_VM_SIZE is required}"
: "${CYCLECLOUD_URN:?CYCLECLOUD_URN is required}"
: "${SCHEDULER_URN:?SCHEDULER_URN is required}"
: "${BURST_COMPUTE_URN:?BURST_COMPUTE_URN is required}"
: "${WINDOWS_URN:?WINDOWS_URN is required}"

CYCLECLOUD_VM_COUNT="${CYCLECLOUD_VM_COUNT:-1}"
SCHEDULER_VM_COUNT="${SCHEDULER_VM_COUNT:-1}"
WINDOWS_VM_COUNT="${WINDOWS_VM_COUNT:-1}"
BURST_NODE_COUNT="${BURST_NODE_COUNT:-1}"
ALTERNATE_BURST_PLACEMENTS_JSON="${ALTERNATE_BURST_PLACEMENTS_JSON:-[]}"

[[ "$BURST_ZONE" =~ ^[123]$ ]] || { echo "BURST_ZONE must be 1, 2, or 3" >&2; exit 3; }
jq -e 'type == "array" and all(.[]; (.region | type == "string" and length > 0) and (.zone | test("^[123]$")))' \
  <<<"$ALTERNATE_BURST_PLACEMENTS_JSON" >/dev/null || {
  echo "ALTERNATE_BURST_PLACEMENTS_JSON must be an array of region/zone objects" >&2
  exit 3
}
if [[ "${SOURCE_REGION,,}" == "${BURST_REGION,,}" ]]; then
  echo "Source and burst regions must differ" >&2
  exit 3
fi

az_timeout_seconds="${AZ_COMMAND_TIMEOUT_SECONDS:-120}"
declare -A sku_data=()
declare -A image_data=()
declare -A usage_data=()

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
  local response
  if [[ ! -v "sku_data[$key]" ]]; then
    progress "Querying VM size $size in $region"
    response="$(run_az vm list-skus --location "$region" --size "$size" --all \
      --query "[?name=='$size'] | [0]" --output json)"
    sku_data["$key"]="${response:-null}"
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

load_usage() {
  local region="$1"
  if [[ ! -v "usage_data[$region]" ]]; then
    progress "Querying compute quota usage in $region"
    usage_data["$region"]="$(run_az vm list-usage --location "$region" --output json)"
  fi
}

image_property() {
  local region="$1" urn="$2" property="$3"
  load_image "$region" "$urn"
  jq -er --arg property "$property" '.[$property]' <<<"${image_data["$region|$urn"]}"
}

sku_property() {
  local region="$1" size="$2" property="$3"
  load_sku "$region" "$size"
  jq -er --arg property "$property" '.[$property]' <<<"${sku_data["$region|$size"]}"
}

size_capability() {
  local region="$1" size="$2" capability="$3"
  load_sku "$region" "$size"
  jq -er --arg capability "$capability" \
    '.capabilities[] | select(.name == $capability) | .value' \
    <<<"${sku_data["$region|$size"]}"
}

check_image() {
  local region="$1" urn="$2"
  local publisher offer sku version
  IFS=: read -r publisher offer sku version <<<"$urn"
  [[ -n "$publisher" && -n "$offer" && -n "$sku" && -n "$version" ]] || {
    echo "Image URN is incomplete: $urn" >&2
    return 1
  }
  load_image "$region" "$urn"
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

role_names=(cyclecloud scheduler windows_admin burst_compute)
role_regions=("$SOURCE_REGION" "$SOURCE_REGION" "$SOURCE_REGION" "$BURST_REGION")
role_sizes=("$CYCLECLOUD_VM_SIZE" "$SCHEDULER_VM_SIZE" "$WINDOWS_VM_SIZE" "$BURST_VM_SIZE")
role_counts=("$CYCLECLOUD_VM_COUNT" "$SCHEDULER_VM_COUNT" "$WINDOWS_VM_COUNT" "$BURST_NODE_COUNT")

role_vcpus() {
  if ! size_capability "${role_regions[$1]}" "${role_sizes[$1]}" vCPUs 2>/dev/null; then
    printf '0\n'
  fi
}

required_for_region() {
  local region="$1" total=0 index
  for index in "${!role_names[@]}"; do
    if [[ "${role_regions[$index],,}" == "${region,,}" ]]; then
      total="$((total + $(role_vcpus "$index") * role_counts[index]))"
    fi
  done
  printf '%s\n' "$total"
}

required_for_family() {
  local region="$1" family="$2" total=0 index role_family
  for index in "${!role_names[@]}"; do
    if [[ "${role_regions[$index],,}" == "${region,,}" ]]; then
      if ! role_family="$(sku_property "${role_regions[$index]}" "${role_sizes[$index]}" family 2>/dev/null)"; then
        continue
      fi
      if [[ "${role_family,,}" == "${family,,}" ]]; then
        total="$((total + $(role_vcpus "$index") * role_counts[index]))"
      fi
    fi
  done
  printf '%s\n' "$total"
}

quota_record() {
  local region="$1" name="$2"
  load_usage "$region"
  jq -ec --arg name "$name" \
    '.[] | select((.name.value // "" | ascii_downcase) == ($name | ascii_downcase)) |
     {
       name: .name.value,
       current: (.currentValue | tonumber),
       limit: (.limit | tonumber)
     }' \
    <<<"${usage_data[$region]}" | head -n 1
}

assess_placement() {
  local region="$1" zone="$2" size="$3" count="$4" regional_required="${5:-}" family_required="${6:-}"
  local key="$region|$size" family vcpus restrictions zones regional family_quota
  local regional_available family_available status="eligible" failure_class="none"

  load_sku "$region" "$size"
  if ! jq -e --arg size "$size" '.name == $size' <<<"${sku_data[$key]}" >/dev/null; then
    jq -n --arg region "$region" --arg zone "$zone" --arg size "$size" \
      '{region:$region, zone:$zone, vm_size:$size, status:"ineligible", failure_class:"sku_unavailable"}'
    return
  fi

  family="$(sku_property "$region" "$size" family)"
  vcpus="$(size_capability "$region" "$size" vCPUs)"
  [[ -n "$regional_required" ]] || regional_required="$((vcpus * count))"
  [[ -n "$family_required" ]] || family_required="$((vcpus * count))"
  zones="$(jq -c --arg region "$region" \
    '[.locationInfo[]? | select((.location | ascii_downcase) == ($region | ascii_downcase)) | .zones[]?] | unique' \
    <<<"${sku_data[$key]}")"
  restrictions="$(jq -c --arg zone "$zone" \
    '[.restrictions[]? |
      select((.type // "") != "Zone" or
        ($zone != "" and ((.restrictionInfo.zones // []) | index($zone)))) |
      {type, reasonCode, restrictionInfo}]' <<<"${sku_data[$key]}")"

  if [[ -n "$zone" ]] && ! jq -e --arg zone "$zone" 'index($zone) != null' <<<"$zones" >/dev/null; then
    status="ineligible"
    failure_class="zonal_restriction"
  elif [[ "$(jq 'length' <<<"$restrictions")" -gt 0 ]]; then
    status="ineligible"
    if jq -e 'any(.[]; .type == "Zone")' <<<"$restrictions" >/dev/null; then
      failure_class="zonal_restriction"
    else
      failure_class="subscription_restriction"
    fi
  fi

  if ! regional="$(quota_record "$region" cores)"; then
    status="inconclusive"
    failure_class="regional_quota_unavailable"
    regional='{"name":"cores","current":null,"limit":null}'
  fi
  if ! family_quota="$(quota_record "$region" "$family")"; then
    status="inconclusive"
    failure_class="family_quota_unavailable"
    family_quota="$(jq -n --arg name "$family" '{name:$name,current:null,limit:null}')"
  fi

  regional_available="$(jq -r 'if .current == null then -1 else .limit - .current end' <<<"$regional")"
  family_available="$(jq -r 'if .current == null then -1 else .limit - .current end' <<<"$family_quota")"
  if (( regional_available >= 0 && regional_available < regional_required )); then
    status="ineligible"
    failure_class="regional_quota_insufficient"
  elif (( family_available >= 0 && family_available < family_required )); then
    status="ineligible"
    failure_class="family_quota_insufficient"
  fi

  jq -n \
    --arg region "$region" --arg zone "$zone" --arg size "$size" --arg family "$family" \
    --arg status "$status" --arg failure_class "$failure_class" \
    --argjson zones "$zones" --argjson restrictions "$restrictions" \
    --argjson count "$count" --argjson vcpus "$vcpus" \
    --argjson regional_required "$regional_required" --argjson family_required "$family_required" \
    --argjson regional "$regional" --argjson family_quota "$family_quota" \
    '{
      region:$region, zone:$zone, vm_size:$size, vm_family:$family,
      planned_count:$count, vcpus_per_vm:$vcpus,
      zones:$zones, restrictions:$restrictions,
      regional_quota:($regional + {
        required:$regional_required,
        available:(if $regional.current == null then null else $regional.limit - $regional.current end),
        projected_remaining:(if $regional.current == null then null else $regional.limit - $regional.current - $regional_required end)
      }),
      family_quota:($family_quota + {
        required:$family_required,
        available:(if $family_quota.current == null then null else $family_quota.limit - $family_quota.current end),
        projected_remaining:(if $family_quota.current == null then null else $family_quota.limit - $family_quota.current - $family_required end)
      }),
      status:$status, failure_class:$failure_class
    }'
}

progress "Checking subscription and regions"
subscription_id="$(run_az account show --query id --output tsv)"
locations="$(run_az account list-locations --query '[].name' --output tsv)"
grep -Fxiq "$SOURCE_REGION" <<<"$locations" || { echo "Unsupported source region: $SOURCE_REGION" >&2; exit 4; }
grep -Fxiq "$BURST_REGION" <<<"$locations" || { echo "Unsupported burst region: $BURST_REGION" >&2; exit 4; }

for index in "${!role_names[@]}"; do
  load_sku "${role_regions[$index]}" "${role_sizes[$index]}"
done
load_usage "$SOURCE_REGION"
load_usage "$BURST_REGION"

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

role_assessments=()
for index in "${!role_names[@]}"; do
  zone=""
  [[ "${role_names[$index]}" == "burst_compute" ]] && zone="$BURST_ZONE"
  if family="$(sku_property "${role_regions[$index]}" "${role_sizes[$index]}" family 2>/dev/null)"; then
    regional_required="$(required_for_region "${role_regions[$index]}")"
    family_required="$(required_for_family "${role_regions[$index]}" "$family")"
    assessment="$(assess_placement "${role_regions[$index]}" "$zone" "${role_sizes[$index]}" \
      "${role_counts[$index]}" "$regional_required" "$family_required")"
  else
    assessment="$(assess_placement "${role_regions[$index]}" "$zone" "${role_sizes[$index]}" \
      "${role_counts[$index]}")"
  fi
  role_assessments+=("$(jq -c --arg role "${role_names[$index]}" '{key:$role,value:.}' <<<"$assessment")")
done
roles_json="$(printf '%s\n' "${role_assessments[@]}" | jq -cs 'from_entries')"

alternate_assessments=()
while IFS= read -r placement; do
  region="$(jq -r '.region' <<<"$placement")"
  zone="$(jq -r '.zone' <<<"$placement")"
  if ! grep -Fxiq "$region" <<<"$locations"; then
    alternate_assessments+=("$(jq -cn --arg region "$region" --arg zone "$zone" \
      '{region:$region,zone:$zone,status:"ineligible",failure_class:"unsupported_region",image_status:"not_checked"}')")
    continue
  fi
  load_sku "$region" "$BURST_VM_SIZE"
  load_usage "$region"
  assessment="$(assess_placement "$region" "$zone" "$BURST_VM_SIZE" "$BURST_NODE_COUNT")"
  if run_az vm image show --location "$region" \
    --publisher "${BURST_COMPUTE_URN%%:*}" \
    --offer "$(cut -d: -f2 <<<"$BURST_COMPUTE_URN")" \
    --sku "$(cut -d: -f3 <<<"$BURST_COMPUTE_URN")" \
    --version "${BURST_COMPUTE_URN##*:}" --output none; then
    assessment="$(jq '. + {image_status:"available"}' <<<"$assessment")"
  else
    assessment="$(jq '. + {status:"ineligible",failure_class:"image_unavailable",image_status:"unavailable"}' <<<"$assessment")"
  fi
  alternate_assessments+=("$(jq -c . <<<"$assessment")")
done < <(jq -c '.[]' <<<"$ALTERNATE_BURST_PLACEMENTS_JSON")
if ((${#alternate_assessments[@]})); then
  alternates_json="$(printf '%s\n' "${alternate_assessments[@]}" | jq -cs .)"
else
  alternates_json='[]'
fi

progress "Checking CycleCloud Marketplace terms"
run_az vm image terms show --urn "$CYCLECLOUD_URN" \
  --query accepted --output tsv | grep -qi '^true$' || {
  echo "CycleCloud Marketplace terms are not accepted for $CYCLECLOUD_URN" >&2
  exit 5
}

overall_status="validated"
if ! jq -e 'all(.[]; .status == "eligible")' <<<"$roles_json" >/dev/null; then
  overall_status="failed"
fi

jq -n \
  --arg subscription_id "$subscription_id" \
  --arg source_region "$SOURCE_REGION" --arg burst_region "$BURST_REGION" --arg burst_zone "$BURST_ZONE" \
  --arg cyclecloud_version "8.9.3" --arg burst_vm_size "$BURST_VM_SIZE" \
  --arg scheduler_urn "$SCHEDULER_URN" --arg burst_compute_urn "$BURST_COMPUTE_URN" \
  --arg image_family "$image_family" --arg image_major "$image_major" \
  --arg image_generation "$scheduler_generation" --arg image_architecture "$scheduler_architecture" \
  --arg overall_status "$overall_status" --argjson roles "$roles_json" --argjson alternates "$alternates_json" \
  '{
    subscription_id:$subscription_id,
    source_region:$source_region,
    burst_region:$burst_region,
    burst_zone:$burst_zone,
    cyclecloud_version:$cyclecloud_version,
    burst_vm_size:$burst_vm_size,
    images:{
      scheduler:{urn:$scheduler_urn},
      burst_compute:{urn:$burst_compute_urn},
      compatibility:{
        status:"validated", os_family:$image_family, os_major:$image_major,
        hyperv_generation:$image_generation, architecture:$image_architecture
      }
    },
    capacity:{
      status:$overall_status,
      assessed_at:(now | todateiso8601),
      roles:$roles,
      alternate_placements:$alternates,
      probe_status:"not_run",
      disclaimer:"Static eligibility and quota checks do not guarantee Azure allocation capacity."
    },
    global_peering:"validated during reviewed Terraform plan"
  }'

if [[ "$overall_status" != "validated" ]]; then
  echo "One or more selected role placements failed quota, SKU, or zonal validation" >&2
  exit 7
fi
progress "All static preflight checks passed"
