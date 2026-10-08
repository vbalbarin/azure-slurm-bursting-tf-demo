#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${AZSLURM_CREDENTIAL_SECRET_ID:?AZSLURM_CREDENTIAL_SECRET_ID is required}"
: "${DEMO_PUBLIC_KEY_SECRET_ID:?DEMO_PUBLIC_KEY_SECRET_ID is required}"
: "${CHEF_NODE_JSON:?CHEF_NODE_JSON is required}"

credential_file=/run/azslurm/credentials
attributes_file="$(mktemp /run/slurm-attributes.XXXXXX.json)"
cleanup() {
  rm -f "$credential_file" "$attributes_file"
}
trap cleanup EXIT

install -d -m 0700 /run/azslurm
az keyvault secret download --id "$AZSLURM_CREDENTIAL_SECRET_ID" \
  --file "$credential_file" --encoding utf-8 1>/dev/null
chmod 0600 "$credential_file"
public_key="$(az keyvault secret show --id "$DEMO_PUBLIC_KEY_SECRET_ID" --query value --output tsv)"
jq --arg public_key "$public_key" \
  '.demo_user.public_key = $public_key' "$CHEF_NODE_JSON" >"$attributes_file"

chef-client --local-mode \
  --policy-name slurm \
  --policy-group demo \
  --json-attributes "$attributes_file" \
  --log_level warn
