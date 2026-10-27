#!/usr/bin/env bash
set -euo pipefail
umask 077

# shellcheck source=/dev/null
source /etc/cyclecloud-first-run.env

: "${CYCLECLOUD_CHEF_PAYLOAD_B64:?CYCLECLOUD_CHEF_PAYLOAD_B64 is required}"
: "${CYCLECLOUD_CHEF_MANIFEST_B64:?CYCLECLOUD_CHEF_MANIFEST_B64 is required}"
: "${CYCLECLOUD_CHEF_SPECIFICATION_B64:?CYCLECLOUD_CHEF_SPECIFICATION_B64 is required}"
: "${CYCLECLOUD_CHEF_POLICY_LOCK_B64:?CYCLECLOUD_CHEF_POLICY_LOCK_B64 is required}"
: "${CYCLECLOUD_CHEF_PAYLOAD_SHA256:?CYCLECLOUD_CHEF_PAYLOAD_SHA256 is required}"
: "${CYCLECLOUD_CHEF_MANIFEST_SHA256:?CYCLECLOUD_CHEF_MANIFEST_SHA256 is required}"
: "${CYCLECLOUD_CHEF_SPECIFICATION_SHA256:?CYCLECLOUD_CHEF_SPECIFICATION_SHA256 is required}"
: "${CYCLECLOUD_CHEF_POLICY_LOCK_SHA256:?CYCLECLOUD_CHEF_POLICY_LOCK_SHA256 is required}"
: "${CYCLECLOUD_VM_RESOURCE_ID:?CYCLECLOUD_VM_RESOURCE_ID is required}"
: "${CYCLECLOUD_CUSTOM_ROLE_DEFINITION_ID:?CYCLECLOUD_CUSTOM_ROLE_DEFINITION_ID is required}"
: "${CYCLECLOUD_CUSTOM_ROLE_DIGEST:?CYCLECLOUD_CUSTOM_ROLE_DIGEST is required}"
: "${CYCLECLOUD_CUSTOM_ROLE_SCOPE:?CYCLECLOUD_CUSTOM_ROLE_SCOPE is required}"

readonly cycle_root=/opt/cycle_server
readonly state_dir=/var/lib/cyclecloud-first-run
readonly secret_dir=/run/cyclecloud-first-run
readonly chef_input_dir=/run/cyclecloud-chef-input
readonly cli_root=/usr/local/cyclecloud-cli
readonly cli_config=/etc/cyclecloud/cli.ini
readonly cli_default_config=/root/.cycle/config.ini

install -d -m 0700 "$state_dir" "$secret_dir" "$chef_input_dir" /etc/cyclecloud
cleanup() {
  rm -rf "$secret_dir" "$chef_input_dir" /tmp/cyclecloud-cli-installer
}
trap cleanup EXIT

if [[ -f "$state_dir/converged" ]]; then
  cleanup
  trap - EXIT
  exit 0
fi

decode_and_verify() {
  local encoded="$1"
  local expected_digest="$2"
  local output="$3"
  [[ "$expected_digest" =~ ^[0-9a-f]{64}$ ]] || {
    echo "Invalid CycleCloud Chef input digest" >&2
    exit 1
  }
  printf '%s' "$encoded" | base64 --decode >"$output"
  chmod 0600 "$output"
  [[ "$(sha256sum "$output" | awk '{print $1}')" == "$expected_digest" ]] || {
    echo "CycleCloud Chef input digest mismatch" >&2
    exit 1
  }
}

decode_and_verify "$CYCLECLOUD_CHEF_PAYLOAD_B64" \
  "$CYCLECLOUD_CHEF_PAYLOAD_SHA256" "$chef_input_dir/cyclecloud.tgz"
decode_and_verify "$CYCLECLOUD_CHEF_MANIFEST_B64" \
  "$CYCLECLOUD_CHEF_MANIFEST_SHA256" "$chef_input_dir/manifest.json"
decode_and_verify "$CYCLECLOUD_CHEF_SPECIFICATION_B64" \
  "$CYCLECLOUD_CHEF_SPECIFICATION_SHA256" "$chef_input_dir/node-specification.json"
decode_and_verify "$CYCLECLOUD_CHEF_POLICY_LOCK_B64" \
  "$CYCLECLOUD_CHEF_POLICY_LOCK_SHA256" "$chef_input_dir/cyclecloud.lock.json"
python3 - "$chef_input_dir/manifest.json" "$chef_input_dir/cyclecloud.lock.json" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

manifest = json.loads(Path(sys.argv[1]).read_text())
lock_path = Path(sys.argv[2])
lock = json.loads(lock_path.read_text())
if manifest.get("policyLockSha256") != hashlib.sha256(lock_path.read_bytes()).hexdigest():
    raise SystemExit("CycleCloud policy lock is not bound to the manifest")
if manifest.get("policyRevision") != lock.get("revision_id"):
    raise SystemExit("CycleCloud policy revision mismatch")
PY
tar --extract --to-stdout --gzip --file "$chef_input_dir/cyclecloud.tgz" \
  chef/bootstrap/linux.sh >"$chef_input_dir/bootstrap-linux.sh"
chmod 0700 "$chef_input_dir/bootstrap-linux.sh"

dnf install -y \
  https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm
dnf install -y azure-cli jq unzip

az login --identity --allow-no-subscriptions --output none
account_name="$(
  az account show \
    --subscription "$AZURE_SUBSCRIPTION_ID" \
    --query name \
    --output tsv
)"
[[ -n "$account_name" ]]
readonly account_name

authorization_retry() {
  local label="$1"
  shift
  local deadline=$((SECONDS + 1800))
  local error_file="$secret_dir/${label}.stderr"
  while ((SECONDS < deadline)); do
    if "$@" 2>"$error_file"; then
      rm -f "$error_file"
      return 0
    fi
    if ! grep -Eqi \
      'AuthorizationFailed|AuthorizationFailure|AuthorizationPermissionMismatch|Forbidden|ForbiddenByRbac|InsufficientAccountPermissions|403|TooManyRequests|429|InternalServerError|ServiceUnavailable|GatewayTimeout|ConnectionError|Connection reset|timed out|Temporary failure in name resolution|5[0-9]{2}' \
      "$error_file"; then
      rm -f "$error_file"
      echo "CycleCloud authorization check failed with a non-retryable response: $label" >&2
      return 1
    fi
    sleep 15
  done
  rm -f "$error_file"
  echo "CycleCloud authorization propagation timed out after 1800 seconds: $label" >&2
  return 1
}

authorization_retry management-access \
  az group show \
  --subscription "$AZURE_SUBSCRIPTION_ID" \
  --name "$CYCLECLOUD_COMPUTE_RESOURCE_GROUP" \
  --output none

sas_file="$secret_dir/locker-user-delegation.sas"
authorization_retry user-delegation \
  az storage container generate-sas \
  --account-name "$CYCLECLOUD_LOCKER_STORAGE" \
  --name cyclecloud \
  --permissions r \
  --expiry "$(date -u -d '+10 minutes' '+%Y-%m-%dT%H:%MZ')" \
  --auth-mode login \
  --as-user \
  --output tsv \
  >"$sas_file"
[[ -s "$sas_file" ]]
rm -f "$sas_file"

download_secret() {
  local secret_name="$1"
  local output_file="$2"
  local encoding="$3"
  authorization_retry secret-read \
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
download_secret chef-license-id "$secret_dir/chef-license-id" utf-8

jq -n \
  --arg vm_resource_id "$CYCLECLOUD_VM_RESOURCE_ID" \
  --arg custom_role_definition_id "$CYCLECLOUD_CUSTOM_ROLE_DEFINITION_ID" \
  --arg custom_role_definition_digest "$CYCLECLOUD_CUSTOM_ROLE_DIGEST" \
  --arg custom_role_assignment_scope "$CYCLECLOUD_CUSTOM_ROLE_SCOPE" \
  --arg checked_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
  '{
    vmResourceId: $vm_resource_id,
    customRoleDefinitionId: $custom_role_definition_id,
    customRoleDefinitionDigest: $custom_role_definition_digest,
    customRoleAssignmentScope: $custom_role_assignment_scope,
    managementAccessVerified: true,
    userDelegationVerified: true,
    secretReadVerified: true,
    checkedAt: $checked_at
  }' >"$state_dir/identity-capabilities.json"
chmod 0600 "$state_dir/identity-capabilities.json"

admin_password="$(<"$secret_dir/admin-password")"
chown cycle_server:cycle_server \
  "$secret_dir/cyclecloud.pfx" \
  "$secret_dir/pfx-password"
chown root:cycle_server "$secret_dir"
chmod 0750 "$secret_dir"
cat >"$secret_dir/import-pfx" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$cycle_root/cycle_server" keystore import_pfx \
  "$secret_dir/cyclecloud.pfx" --pass "\$(<"$secret_dir/pfx-password")"
EOF
chown root:cycle_server "$secret_dir/import-pfx"
chmod 0750 "$secret_dir/import-pfx"

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

sudo -u cycle_server "$secret_dir/import-pfx"
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
  --arg account_name "$account_name" \
  '{
    AcceptMarketplaceTerms: true,
    AuthType: "ManagedIdentity",
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
if grep -Fqx 'Account not found' <<<"$account_details"; then
  echo "CycleCloud provider account creation failed" >&2
  exit 1
fi

rm -rf /tmp/cyclecloud-cli-installer
touch "$state_dir/complete"

CHEF_POLICY_NAME=cyclecloud \
CHEF_POLICY_ARCHIVE_PATH="$chef_input_dir/cyclecloud.tgz" \
CHEF_MANIFEST_PATH="$chef_input_dir/manifest.json" \
CHEF_NODE_SPECIFICATION_PATH="$chef_input_dir/node-specification.json" \
CHEF_LICENSE_ID_FILE="$secret_dir/chef-license-id" \
  "$chef_input_dir/bootstrap-linux.sh"

/opt/slurm-demo/current/chef/bin/converge-cyclecloud.sh

touch "$state_dir/converged"
cleanup
trap - EXIT
