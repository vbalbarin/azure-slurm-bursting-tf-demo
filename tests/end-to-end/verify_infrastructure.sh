#!/usr/bin/env bash
set -euo pipefail

for command in az jq; do
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
cyclecloud_address="$(jq -r '.private_hosts.cyclecloud.private_address' "$INVENTORY_FILE")"
cyclecloud_fqdn="$(
  jq -r '.application_access.cyclecloud_private_url | sub("^https://"; "")' \
    "$INVENTORY_FILE"
)"
key_vault_fqdn="$(jq -r '.key_vault_private_name' "$INVENTORY_FILE")"
resource_group_name="$(
  az vm list \
    --query "[?name=='${cyclecloud_name}'].resourceGroup | [0]" \
    --output tsv
)"
[[ -n "$resource_group_name" ]]

cyclecloud_record_name="${cyclecloud_fqdn%%.*}"
cyclecloud_zone_name="${cyclecloud_fqdn#*.}"
az network private-dns record-set a show \
  --resource-group "$resource_group_name" \
  --zone-name "$cyclecloud_zone_name" \
  --name "$cyclecloud_record_name" \
  --query 'aRecords[].ipv4Address' \
  --output tsv | grep -Fqx "$cyclecloud_address"

key_vault_record_name="${key_vault_fqdn%%.*}"
key_vault_zone_name="${key_vault_fqdn#*.}"
az network private-dns record-set a show \
  --resource-group "$resource_group_name" \
  --zone-name "$key_vault_zone_name" \
  --name "$key_vault_record_name" \
  --query 'length(aRecords)' \
  --output tsv | grep -Eq '^[1-9][0-9]*$'

for host_key in cyclecloud scheduler windows_admin; do
  public_address="$(jq -r ".private_hosts.${host_key}.public_address // empty" "$INVENTORY_FILE")"
  [[ -z "$public_address" ]] || { echo "$host_key unexpectedly has a public address" >&2; exit 4; }
done

environment_name="$(jq -r '.environment_name' "$INVENTORY_FILE")"
source_nat_id="$(
  az network nat gateway list \
    --query "[?name=='${environment_name}-source-nat' && provisioningState=='Succeeded'].id | [0]" \
    --output tsv
)"
burst_nat_id="$(
  az network nat gateway list \
    --query "[?name=='${environment_name}-burst-nat' && provisioningState=='Succeeded'].id | [0]" \
    --output tsv
)"
[[ -n "$source_nat_id" && -n "$burst_nat_id" && "$source_nat_id" != "$burst_nat_id" ]]

az network nat gateway show --ids "$source_nat_id" \
  --query 'length(publicIpAddresses)' --output tsv | grep -qx '1'
az network nat gateway show --ids "$burst_nat_id" \
  --query 'length(publicIpAddresses)' --output tsv | grep -qx '1'

for subnet in snet-access snet-management; do
  az network vnet list \
    --query "[?name=='vnet-source'].subnets[] | [?name=='${subnet}'].natGateway.id | [0]" \
    --output tsv | grep -Fqx "$source_nat_id"
done

az network vnet list \
  --query "[?name=='vnet-burst'].subnets[] | [?name=='snet-compute'].natGateway.id | [0]" \
  --output tsv | grep -Fqx "$burst_nat_id"

az network bastion list \
  --query "[?name=='${environment_name}-bastion' && provisioningState=='Succeeded' && sku.name=='Standard'] | length(@)" \
  --output tsv | grep -qx '1'
