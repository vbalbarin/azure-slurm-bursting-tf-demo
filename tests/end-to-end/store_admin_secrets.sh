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
: "${ADMIN_SECRET_EVIDENCE_FILE:?ADMIN_SECRET_EVIDENCE_FILE is required}"

for file in \
  "$CYCLECLOUD_SSH_PRIVATE_KEY_FILE" \
  "$SCHEDULER_SSH_PRIVATE_KEY_FILE" \
  "$WINDOWS_ADMIN_PASSWORD_FILE"; do
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

write_secret() {
  local name="$1"
  local file="$2"
  local content_type="$3"
  az keyvault secret set \
    --vault-name "$vault_name" \
    --name "$name" \
    --file "$file" \
    --encoding utf-8 \
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
} | jq -s '{
  status: "stored",
  secret_references: map({id, name})
}' >"$ADMIN_SECRET_EVIDENCE_FILE"

jq -e '
  .status == "stored" and
  (.secret_references | length) == 3 and
  all(.secret_references[]; (.id | type == "string") and (.name | type == "string"))
' "$ADMIN_SECRET_EVIDENCE_FILE" >/dev/null
