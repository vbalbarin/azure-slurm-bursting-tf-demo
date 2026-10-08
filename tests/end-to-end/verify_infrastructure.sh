#!/usr/bin/env bash
set -euo pipefail

for command in az jq dig nc; do
  command -v "$command" >/dev/null || { echo "Missing required command: $command" >&2; exit 2; }
done

: "${INVENTORY_FILE:?INVENTORY_FILE is required}"
jq -e '
  .source_region != .burst_region and
  .private_hosts.cyclecloud.private_address != null and
  .private_hosts.scheduler.private_address != null and
  .private_hosts.windows_admin.private_address != null
' "$INVENTORY_FILE" >/dev/null

if grep -Eqi '"(password|private_key|secret_value)"[[:space:]]*:' "$INVENTORY_FILE"; then
  echo "Inventory contains a prohibited secret-shaped field" >&2
  exit 3
fi

cyclecloud_name="$(jq -r '.private_hosts.cyclecloud.name' "$INVENTORY_FILE")"
key_vault_name="$(jq -r '.key_vault_private_name' "$INVENTORY_FILE")"
dig +short "$cyclecloud_name" | grep -Eq '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)'
dig +short "$key_vault_name" | grep -Eq '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)'

for host_key in cyclecloud scheduler windows_admin; do
  public_address="$(jq -r ".private_hosts.${host_key}.public_address // empty" "$INVENTORY_FILE")"
  [[ -z "$public_address" ]] || { echo "$host_key unexpectedly has a public address" >&2; exit 4; }
done

az network bastion list --query "[?provisioningState=='Succeeded'] | length(@)" --output tsv | grep -qv '^0$'
