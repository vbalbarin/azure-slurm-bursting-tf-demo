#!/usr/bin/env bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "Source this script so exports persist: source $0 [demo.tfvars]" >&2
  exit 2
fi

_export_preflight_env() {
  local script_dir repository_root tfvars_file expression encoded_json values_json
  local evaluation_root evaluation_status
  local name value

  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  repository_root="$(cd -- "$script_dir/../.." && pwd)"
  tfvars_file="${1:-$repository_root/terraform/environments/demo.tfvars}"

  command -v terraform >/dev/null || {
    echo "Missing required command: terraform" >&2
    return 2
  }
  command -v jq >/dev/null || {
    echo "Missing required command: jq" >&2
    return 2
  }
  [[ -f "$tfvars_file" ]] || {
    echo "Terraform variable file does not exist: $tfvars_file" >&2
    return 2
  }
  tfvars_file="$(realpath "$tfvars_file")"

  expression="$(cat <<'EOF'
jsonencode({
  SOURCE_REGION = var.source_region,
  BURST_REGION = var.burst_region,
  BURST_ZONE = var.burst_zone,
  ALTERNATE_BURST_PLACEMENTS_JSON = var.alternate_burst_placements,
  CYCLECLOUD_VM_SIZE = var.cyclecloud_vm_size,
  SCHEDULER_VM_SIZE = var.scheduler_vm_size,
  WINDOWS_VM_SIZE = var.windows_vm_size,
  BURST_VM_SIZE = var.burst_vm_size,
  CYCLECLOUD_VM_COUNT = var.cyclecloud_vm_count,
  SCHEDULER_VM_COUNT = var.scheduler_vm_count,
  WINDOWS_VM_COUNT = var.windows_vm_count,
  BURST_NODE_COUNT = var.burst_node_count,
  CYCLECLOUD_URN = join(":", [
    var.cyclecloud_image.publisher,
    var.cyclecloud_image.offer,
    var.cyclecloud_image.sku,
    var.cyclecloud_image.version
  ]),
  SCHEDULER_URN = join(":", [
    var.scheduler_image.publisher,
    var.scheduler_image.offer,
    var.scheduler_image.sku,
    var.scheduler_image.version
  ]),
  BURST_COMPUTE_URN = join(":", [
    var.burst_compute_image.publisher,
    var.burst_compute_image.offer,
    var.burst_compute_image.sku,
    var.burst_compute_image.version
  ]),
  WINDOWS_URN = join(":", [
    var.windows_image.publisher,
    var.windows_image.offer,
    var.windows_image.sku,
    var.windows_image.version
  ])
})
EOF
)"
  expression="${expression//$'\n'/ }"

  evaluation_root="$(mktemp -d)"
  cp "$repository_root/terraform/variables.tf" "$evaluation_root/variables.tf"
  if encoded_json="$(
    printf '%s\n' "$expression" |
      terraform -chdir="$evaluation_root" console \
        -var-file="$tfvars_file"
  )"; then
    evaluation_status=0
  else
    evaluation_status="$?"
  fi
  rm -f "$evaluation_root/variables.tf"
  rmdir "$evaluation_root"
  if [[ "$evaluation_status" -ne 0 ]]; then
    echo "Terraform could not evaluate preflight values from $tfvars_file" >&2
    return 1
  fi
  if ! values_json="$(jq -er 'fromjson | with_entries(
      .value |= if type == "array" or type == "object" then tojson else tostring end
    )' <<<"$encoded_json")"; then
    echo "Terraform returned invalid preflight JSON" >&2
    return 1
  fi

  while IFS=$'\t' read -r name value; do
    printf -v "$name" '%s' "$value"
    export "${name?}"
    printf 'export %s=%q\n' "$name" "$value"
  done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' <<<"$values_json")

  export TFVARS_FILE="$tfvars_file"
  printf 'export TFVARS_FILE=%q\n' "$TFVARS_FILE"
}

_export_preflight_env "$@"
_export_preflight_env_status="$?"
unset -f _export_preflight_env
return "$_export_preflight_env_status"
