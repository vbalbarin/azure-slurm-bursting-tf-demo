#!/usr/bin/env bash
set -euo pipefail

command -v jq >/dev/null || {
  echo "Missing required command: jq" >&2
  exit 2
}

preflight_file="${1:-${PREFLIGHT_RESULTS_FILE:-}}"
[[ -n "$preflight_file" ]] || {
  echo "Usage: $0 PREFLIGHT_RESULTS_FILE" >&2
  exit 2
}
[[ -f "$preflight_file" ]] || {
  echo "Preflight results file does not exist: $preflight_file" >&2
  exit 2
}

jq -e '
  type == "object" and
  (.subscription_id | type == "string" and length > 0) and
  (.source_region | type == "string" and length > 0) and
  (.burst_region | type == "string" and length > 0) and
  (.burst_zone | type == "string" and length > 0) and
  (.images.scheduler.urn | type == "string" and length > 0) and
  (.images.burst_compute.urn | type == "string" and length > 0) and
  (.images.compatibility | type == "object") and
  (.capacity.status | type == "string" and length > 0) and
  (.capacity.roles | type == "object" and length > 0) and
  (.capacity.alternate_placements | type == "array")
' "$preflight_file" >/dev/null || {
  echo "Preflight results do not match the expected schema: $preflight_file" >&2
  exit 3
}

jq -r '
  def md:
    if . == null or . == "" then
      "n/a"
    else
      tostring | gsub("\\|"; "\\|") | gsub("[\r\n]+"; " ")
    end;
  def role_name:
    if . == "cyclecloud" then "CycleCloud"
    elif . == "scheduler" then "Scheduler"
    elif . == "windows_admin" then "Windows administration"
    elif . == "burst_compute" then "Burst compute"
    else . | gsub("_"; " ")
    end;
  def zones:
    if type != "array" or length == 0 then "none" else map(md) | join(", ") end;
  def restrictions:
    if type != "array" or length == 0 then
      "none"
    else
      map(
        ((.type | md) + ": " + (.reasonCode | md)) +
        (if .restrictionInfo.locations? then
          " (" + (.restrictionInfo.locations | map(md) | join(", ")) + ")"
        else "" end)
      ) | join("; ")
    end;
  def role_rows:
    .capacity.roles | to_entries | map(
      "| \(.key | role_name | md) | \(.value.status | md) | \(.value.failure_class | md) | " +
      "\(.value.region | md) | \(.value.zone | md) | \(.value.vm_size | md) | " +
      "\(.value.planned_count | md) | \(.value.vcpus_per_vm | md) | " +
      "\(.value.zones | zones) | \(.value.restrictions | restrictions) |"
    );
  def quota_rows:
    .capacity.roles | to_entries | map(
      .key as $role | .value as $value |
      ["regional_quota", "family_quota"] | map(
        . as $scope | $value[$scope] as $quota |
        "| \($role | role_name | md) | " +
        "\(if $scope == "regional_quota" then "Regional" else "VM family" end) | " +
        "\($quota.name | md) | \($quota.current | md) | \($quota.limit | md) | " +
        "\($quota.required | md) | \($quota.available | md) | " +
        "\($quota.projected_remaining | md) |"
      )
    ) | flatten;
  def alternate_rows:
    if .capacity.alternate_placements | length == 0 then
      ["| none | n/a | n/a | n/a | n/a | n/a | n/a |"]
    else
      .capacity.alternate_placements | to_entries | map(
        "| \(.key + 1) | \(.value.region | md) | \(.value.zone | md) | " +
        "\(.value.vm_size | md) | \(.value.status | md) | " +
        "\(.value.failure_class | md) | \(.value.image_status | md) |"
      )
    end;
  def findings:
    (
      [
        .capacity.roles | to_entries[] |
        select(.value.status != "eligible") |
        "- **\(.key | role_name | md)** reports status `\(.value.status | md)` " +
        "with failure class `\(.value.failure_class | md)`."
      ] +
      [
        .capacity.roles | to_entries[] |
        .value as $value |
        select(
          ($value.zone | type == "string" and length > 0) and
          ($value.zones | type == "array") and
          (($value.zones | index($value.zone)) == null)
        ) |
        "- **\(.key | role_name | md)** selects zone `\($value.zone | md)`, but Azure reports " +
        "available zones `\($value.zones | zones)`."
      ] +
      [
        .capacity.roles | to_entries[] |
        select(.value.restrictions | type == "array" and length > 0) |
        "- **\(.key | role_name | md)** has Azure restrictions: " +
        "\(.value.restrictions | restrictions)."
      ] +
      [
        .capacity.roles | to_entries[] |
        .key as $role | .value as $value |
        ["regional_quota", "family_quota"][] as $scope |
        $value[$scope] as $quota |
        select(($quota.available | tonumber) < ($quota.required | tonumber)) |
        "- **\($role | role_name | md)** has insufficient " +
        "\(if $scope == "regional_quota" then "regional" else "VM-family" end) quota: " +
        "\($quota.available | md) available and \($quota.required | md) required."
      ] +
      [
        .capacity.alternate_placements[] |
        select(.status != "eligible") |
        "- Alternate `\(.region | md)` zone `\(.zone | md)` is `\(.status | md)` " +
        "with failure class `\(.failure_class | md)`."
      ]
    ) as $items |
    if $items | length == 0 then ["- None."] else $items end;

  [
    "# Azure Preflight Summary",
    "",
    "> Generated from the machine-readable preflight result. The JSON remains the authoritative evidence.",
    "",
    "## Overview",
    "",
    "| Field | Value |",
    "|---|---|",
    "| Overall capacity status | \(.capacity.status | md) |",
    "| Assessed at | \(.capacity.assessed_at | md) |",
    "| Subscription | \(.subscription_id | md) |",
    "| Source region | \(.source_region | md) |",
    "| Burst placement | \(.burst_region | md), zone \(.burst_zone | md) |",
    "| CycleCloud version | \(.cyclecloud_version | md) |",
    "| Burst VM size | \(.burst_vm_size | md) |",
    "| Capacity probe | \(.capacity.probe_status | md) |",
    "",
    "## Image Compatibility",
    "",
    "| Image | URN |",
    "|---|---|",
    "| Scheduler | \(.images.scheduler.urn | md) |",
    "| Burst compute | \(.images.burst_compute.urn | md) |",
    "",
    "| Check | Value |",
    "|---|---|",
    "| Status | \(.images.compatibility.status | md) |",
    "| OS family | \(.images.compatibility.os_family | md) |",
    "| OS major | \(.images.compatibility.os_major | md) |",
    "| Hyper-V generation | \(.images.compatibility.hyperv_generation | md) |",
    "| Architecture | \(.images.compatibility.architecture | md) |",
    "",
    "## Role Placement",
    "",
    "| Role | Status | Failure class | Region | Zone | VM size | Count | vCPU/VM | Available zones | Restrictions |",
    "|---|---|---|---|---|---|---:|---:|---|---|"
  ] +
  role_rows +
  [
    "",
    "## Quota",
    "",
    "| Role | Scope | Quota name | Current | Limit | Required | Available | Projected remaining |",
    "|---|---|---|---:|---:|---:|---:|---:|"
  ] +
  quota_rows +
  [
    "",
    "## Alternate Placements",
    "",
    "| Order | Region | Zone | VM size | Status | Failure class | Image status |",
    "|---:|---|---|---|---|---|---|"
  ] +
  alternate_rows +
  [
    "",
    "## Blocking Findings",
    ""
  ] +
  findings +
  [
    "",
    "## Capacity Disclaimer",
    "",
    (.capacity.disclaimer | md),
    ""
  ] |
  join("\n")
' "$preflight_file"
