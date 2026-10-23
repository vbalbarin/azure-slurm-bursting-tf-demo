#!/usr/bin/env bash
set -euo pipefail
umask 077

source /etc/cyclecloud-first-run.env

readonly cycle_root=/opt/cycle_server
readonly state_dir=/var/lib/cyclecloud-first-run
readonly secret_dir=/run/cyclecloud-first-run
readonly cli_root=/usr/local/cyclecloud-cli
readonly cli_config=/etc/cyclecloud/cli.ini
readonly cli_default_config=/root/.cycle/config.ini

install -d -m 0700 "$state_dir" "$secret_dir" /etc/cyclecloud
cleanup() {
  rm -rf "$secret_dir" /tmp/cyclecloud-cli-installer
}
trap cleanup EXIT

dnf install -y \
  https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm
dnf install -y azure-cli jq unzip

az login --identity --client-id "$CYCLECLOUD_CONTROL_IDENTITY_CLIENT_ID" \
  --allow-no-subscriptions --output none
account_name="$(
  az account show \
    --subscription "$AZURE_SUBSCRIPTION_ID" \
    --query name \
    --output tsv
)"
[[ -n "$account_name" ]]
readonly account_name

download_secret() {
  local secret_name="$1"
  local output_file="$2"
  local encoding="$3"
  az keyvault secret download \
    --vault-name "$CYCLECLOUD_KEY_VAULT_NAME" \
    --name "$secret_name" \
    --file "$output_file" \
    --encoding "$encoding" \
    --overwrite \
    --output none
  chmod 0600 "$output_file"
}

download_secret cyclecloud-admin-password "$secret_dir/admin-password" utf-8
download_secret cyclecloud-tls-pfx "$secret_dir/cyclecloud.pfx" base64
download_secret cyclecloud-tls-pfx-password "$secret_dir/pfx-password" utf-8

admin_password="$(<"$secret_dir/admin-password")"
pfx_password="$(<"$secret_dir/pfx-password")"
chown cycle_server:cycle_server \
  "$secret_dir/cyclecloud.pfx" \
  "$secret_dir/pfx-password"
chown root:cycle_server "$secret_dir"
chmod 0750 "$secret_dir"

"$cycle_root/cycle_server" start
for _ in {1..60}; do
  curl --fail --silent --show-error --insecure https://localhost/ >/dev/null 2>&1 &&
    break
  sleep 5
done
curl --fail --silent --show-error --insecure https://localhost/ >/dev/null

if [[ ! -f "$state_dir/account-imported" ]]; then
  CYCLECLOUD_ADMIN_USERNAME="$CYCLECLOUD_ADMIN_USERNAME" \
    ADMIN_PASSWORD="$admin_password" \
    python3 - <<'PY'
import json
import os
from pathlib import Path

username = os.environ["CYCLECLOUD_ADMIN_USERNAME"]
records = [
    {
        "AdType": "Application.Setting",
        "Name": "cycleserver.installation.initial_user",
        "Value": username,
    },
    {
        "AdType": "AuthenticatedUser",
        "Name": username,
        "RawPassword": os.environ["ADMIN_PASSWORD"],
        "Superuser": True,
    },
    {
        "AdType": "Application.Setting",
        "Name": "cycleserver.installation.complete",
        "Value": True,
    },
]
path = Path("/opt/cycle_server/config/data/cyclecloud_account.json")
path.write_text(json.dumps(records))
path.chmod(0o600)
PY
  chown cycle_server:cycle_server \
    "$cycle_root/config/data/cyclecloud_account.json"
  for _ in {1..30}; do
    [[ -f "$cycle_root/config/data/cyclecloud_account.json.imported" ]] && break
    sleep 2
  done
  [[ -f "$cycle_root/config/data/cyclecloud_account.json.imported" ]]
  touch "$state_dir/account-imported"
fi

sudo -u cycle_server "$cycle_root/cycle_server" keystore import_pfx \
  "$secret_dir/cyclecloud.pfx" --pass "$pfx_password"
"$cycle_root/cycle_server" stop
"$cycle_root/cycle_server" start

if [[ ! -x "$cli_root/bin/cyclecloud" ]]; then
  rm -rf /tmp/cyclecloud-cli-installer
  unzip -q "$cycle_root/tools/cyclecloud-cli.zip" \
    -d /tmp/cyclecloud-cli-installer
  python3 \
    /tmp/cyclecloud-cli-installer/cyclecloud-cli-installer/install.py \
    -y --installdir "$cli_root" --system
fi

"$cli_root/bin/cyclecloud" --config="$cli_config" initialize \
  --batch \
  --force \
  --url=https://localhost \
  --verify-ssl=false \
  --username="$CYCLECLOUD_ADMIN_USERNAME" \
  --password="$admin_password"
chmod 0600 "$cli_config"
install -d -m 0700 "$(dirname "$cli_default_config")"
ln -sfn "$cli_config" "$cli_default_config"

jq -n \
  --arg subscription_id "$AZURE_SUBSCRIPTION_ID" \
  --arg resource_group "$CYCLECLOUD_COMPUTE_RESOURCE_GROUP" \
  --arg location "$CYCLECLOUD_BURST_REGION" \
  --arg storage_account "$CYCLECLOUD_LOCKER_STORAGE" \
  --arg locker_identity "$CYCLECLOUD_LOCKER_IDENTITY_RESOURCE_ID" \
  --arg client_id "$CYCLECLOUD_CONTROL_IDENTITY_CLIENT_ID" \
  --arg account_name "$account_name" \
  '{
    AcceptMarketplaceTerms: true,
    AuthType: "ManagedIdentity",
    AzureRMClientId: $client_id,
    AzureRMSubscriptionId: $subscription_id,
    AzureResourceGroup: $resource_group,
    DefaultAccount: true,
    Environment: "public",
    LockerAuthMode: "ManagedIdentity",
    LockerIdentity: $locker_identity,
    Location: $location,
    Name: $account_name,
    PredefinedCreds: true,
    Provider: "azure",
    ProviderId: $subscription_id,
    RMStorageAccount: $storage_account,
    RMStorageContainer: "cyclecloud"
  }' >"$secret_dir/provider.json"

account_details="$("$cli_root/bin/cyclecloud" account show "$account_name" 2>&1)"
if grep -Fqx 'Account not found' <<<"$account_details"; then
  "$cli_root/bin/cyclecloud" account create -f "$secret_dir/provider.json"
fi
account_details="$("$cli_root/bin/cyclecloud" account show "$account_name" 2>&1)"
! grep -Fqx 'Account not found' <<<"$account_details"

cleanup
trap - EXIT
touch "$state_dir/complete"
