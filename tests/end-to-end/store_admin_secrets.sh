#!/usr/bin/env bash
set -euo pipefail
umask 077

for command in az jq terraform; do
  command -v "$command" >/dev/null || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 2
  }
done

: "${CYCLECLOUD_SSH_PRIVATE_KEY_FILE:?CYCLECLOUD_SSH_PRIVATE_KEY_FILE is required}"
: "${SCHEDULER_SSH_PRIVATE_KEY_FILE:?SCHEDULER_SSH_PRIVATE_KEY_FILE is required}"
: "${WINDOWS_ADMIN_PASSWORD_FILE:?WINDOWS_ADMIN_PASSWORD_FILE is required}"
: "${CYCLECLOUD_ADMIN_PASSWORD_FILE:?CYCLECLOUD_ADMIN_PASSWORD_FILE is required}"
: "${CYCLECLOUD_TLS_PFX_FILE:?CYCLECLOUD_TLS_PFX_FILE is required}"
: "${CYCLECLOUD_TLS_PFX_PASSWORD_FILE:?CYCLECLOUD_TLS_PFX_PASSWORD_FILE is required}"
: "${CYCLECLOUD_TLS_CA_FILE:?CYCLECLOUD_TLS_CA_FILE is required}"
: "${CHEF_LICENSE_ID_FILE:?CHEF_LICENSE_ID_FILE is required}"
: "${ADMIN_PASSWORD_EVIDENCE_FILE:?ADMIN_PASSWORD_EVIDENCE_FILE is required}"
: "${ADMIN_SECRET_EVIDENCE_FILE:?ADMIN_SECRET_EVIDENCE_FILE is required}"

[[ -f "$ADMIN_PASSWORD_EVIDENCE_FILE" ]] || {
  printf 'Administrative password evidence does not exist\n' >&2
  exit 2
}
[[ "$(stat -c '%a' "$ADMIN_PASSWORD_EVIDENCE_FILE")" == "600" ]] || {
  printf 'Administrative password evidence must have mode 0600\n' >&2
  exit 2
}
jq -e '
  .schemaVersion == 1 and
  (.status == "generated" or .status == "preserved") and
  .policyProfile == "interactive-admin-v1" and
  .uniquenessValidated == true and
  .protectedModesValidated == true and
  (
    (.status == "generated" and .newValuePolicyValidated == true) or
    (.status == "preserved" and .newValuePolicyValidated == null)
  ) and
  (.completedAt | type == "string") and
  (.targets | type == "array" and length == 2) and
  (
    [.targets[] | select(
      .target == "windows" and
      .account == "windowsadmin" and
      .secretName == "windows-admin-password" and
      .disposition == $status
    )] | length == 1
  ) and
  (
    [.targets[] | select(
      .target == "cyclecloud" and
      .account == "hpcadmin" and
      .secretName == "cyclecloud-admin-password" and
      .disposition == $status
    )] | length == 1
  )
' --arg status "$(jq -r '.status' "$ADMIN_PASSWORD_EVIDENCE_FILE")" \
  "$ADMIN_PASSWORD_EVIDENCE_FILE" >/dev/null || {
  printf 'Administrative password evidence is not accepted\n' >&2
  exit 2
}

for file in \
  "$CYCLECLOUD_SSH_PRIVATE_KEY_FILE" \
  "$SCHEDULER_SSH_PRIVATE_KEY_FILE" \
  "$WINDOWS_ADMIN_PASSWORD_FILE" \
  "$CYCLECLOUD_ADMIN_PASSWORD_FILE" \
  "$CYCLECLOUD_TLS_PFX_FILE" \
  "$CYCLECLOUD_TLS_PFX_PASSWORD_FILE" \
  "$CYCLECLOUD_TLS_CA_FILE" \
  "$CHEF_LICENSE_ID_FILE"; do
  [[ -f "$file" ]] || {
    printf 'Protected credential file does not exist: %s\n' "$file" >&2
    exit 2
  }
  [[ "$(stat -c '%a' "$file")" == "600" ]] || {
    printf 'Protected credential file must have mode 0600: %s\n' "$file" >&2
    exit 2
  }
done

inventory="$(terraform -chdir=terraform output -json inventory)"
vault_name="$(jq -er '.key_vault_private_name | split(".")[0]' <<<"$inventory")"
cyclecloud_name="cyclecloud-admin-ssh-private-key"
scheduler_name="scheduler-admin-ssh-private-key"
windows_name="windows-admin-password"
cyclecloud_admin_name="cyclecloud-admin-password"
cyclecloud_tls_name="cyclecloud-tls-pfx"
cyclecloud_tls_password_name="cyclecloud-tls-pfx-password"
cyclecloud_ca_name="cyclecloud-tls-ca"
chef_license_name="chef-license-id"

write_secret() {
  local name="$1"
  local file="$2"
  local content_type="$3"
  local encoding="${4:-utf-8}"
  az keyvault secret set \
    --vault-name "$vault_name" \
    --name "$name" \
    --file "$file" \
    --encoding "$encoding" \
    --content-type "$content_type" \
    --query '{id:id,name:name}' \
    --output json
}

mkdir -p "$(dirname "$ADMIN_SECRET_EVIDENCE_FILE")"
{
  write_secret "$cyclecloud_name" "$CYCLECLOUD_SSH_PRIVATE_KEY_FILE" \
    "application/x-pem-file"
  write_secret "$scheduler_name" "$SCHEDULER_SSH_PRIVATE_KEY_FILE" \
    "application/x-pem-file"
  write_secret "$windows_name" "$WINDOWS_ADMIN_PASSWORD_FILE" \
    "text/plain"
  write_secret "$cyclecloud_admin_name" "$CYCLECLOUD_ADMIN_PASSWORD_FILE" \
    "text/plain"
  write_secret "$cyclecloud_tls_name" "$CYCLECLOUD_TLS_PFX_FILE" \
    "application/x-pkcs12" base64
  write_secret "$cyclecloud_tls_password_name" "$CYCLECLOUD_TLS_PFX_PASSWORD_FILE" \
    "text/plain"
  write_secret "$cyclecloud_ca_name" "$CYCLECLOUD_TLS_CA_FILE" \
    "application/x-pem-file"
  write_secret "$chef_license_name" "$CHEF_LICENSE_ID_FILE" \
    "text/plain"
} | jq -s '{
  status: "stored",
  secret_references: map({id, name})
}' >"$ADMIN_SECRET_EVIDENCE_FILE"

jq -e '
  .status == "stored" and
  (.secret_references | length) == 8 and
  all(.secret_references[]; (.id | type == "string") and (.name | type == "string"))
' "$ADMIN_SECRET_EVIDENCE_FILE" >/dev/null
