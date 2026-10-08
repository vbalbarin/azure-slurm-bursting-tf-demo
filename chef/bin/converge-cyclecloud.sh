#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${CYCLECLOUD_CREDENTIAL_SECRET_ID:?CYCLECLOUD_CREDENTIAL_SECRET_ID is required}"
: "${CHEF_NODE_JSON:?CHEF_NODE_JSON is required}"

credential_file=/run/cyclecloud/credentials
cleanup() {
  rm -f "$credential_file"
}
trap cleanup EXIT
install -d -m 0700 /run/cyclecloud
az keyvault secret download --id "$CYCLECLOUD_CREDENTIAL_SECRET_ID" \
  --file "$credential_file" --encoding utf-8 1>/dev/null
chmod 0600 "$credential_file"

chef-client --local-mode \
  --policy-name cyclecloud \
  --policy-group demo \
  --json-attributes "$CHEF_NODE_JSON" \
  --log_level warn
