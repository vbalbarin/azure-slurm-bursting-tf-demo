#!/usr/bin/env bash
set -euo pipefail
umask 077

for command in az jq sha256sum terraform; do
  command -v "$command" >/dev/null || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 2
  }
done

: "${EVIDENCE_DIR:?EVIDENCE_DIR is required}"

foundation_evidence="$EVIDENCE_DIR/provisioning.json"
stack_evidence="$EVIDENCE_DIR/cyclecloud-stack/deployment-stack.json"
vm_evidence="$EVIDENCE_DIR/cyclecloud-stack/virtual-machine.json"
key_vault_evidence="$EVIDENCE_DIR/key-vault-hardening.json"
admin_secret_evidence="$EVIDENCE_DIR/admin-secret-references.json"

for file in \
  "$foundation_evidence" \
  "$stack_evidence" \
  "$vm_evidence" \
  "$key_vault_evidence" \
  "$admin_secret_evidence"; do
  [[ -f "$file" ]] || {
    printf 'Required provisioning evidence is missing: %s\n' "$file" >&2
    exit 2
  }
done

jq -e '
  .status == "terraform_foundation_only" and
  .acceptance_complete == false
' "$foundation_evidence" >/dev/null

jq -e '
  .publicNetworkAccess == "Disabled" and
  .defaultAction == "Deny" and
  (.ipRules | length) == 0
' "$key_vault_evidence" >/dev/null

jq -e '
  .status == "stored" and
  (.secret_references | length) == 7
' "$admin_secret_evidence" >/dev/null

deployment="$(terraform -chdir=terraform output -json cyclecloud_deployment)"
expected_vm_name="$(jq -er '.vm_name' <<<"$deployment")"
expected_nic_id="$(jq -er '.nic_resource_id | ascii_downcase' <<<"$deployment")"

jq -e \
  --arg vm_name "$expected_vm_name" \
  --arg nic_id "$expected_nic_id" \
  --arg publisher "$(jq -er '.image.publisher | ascii_downcase' <<<"$deployment")" \
  --arg offer "$(jq -er '.image.offer | ascii_downcase' <<<"$deployment")" \
  --arg sku "$(jq -er '.image.sku | ascii_downcase' <<<"$deployment")" \
  --arg version "$(jq -er '.image.version' <<<"$deployment")" \
  '
    .name == $vm_name and
    (.storageProfile.imageReference.publisher | ascii_downcase) == $publisher and
    (.storageProfile.imageReference.offer | ascii_downcase) == $offer and
    (.storageProfile.imageReference.sku | ascii_downcase) == $sku and
    .storageProfile.imageReference.version == $version and
    any(.storageProfile.dataDisks[]; .lun == 0) and
    (.networkProfile.networkInterfaces | length) == 1 and
    (.networkProfile.networkInterfaces[0].id | ascii_downcase) == $nic_id
  ' "$vm_evidence" >/dev/null

foundation_tmp="$(mktemp "${foundation_evidence}.XXXXXX")"
trap 'rm -f "$foundation_tmp"' EXIT
jq \
  --arg stack_digest "$(sha256sum "$stack_evidence" | awk '{print $1}')" \
  --arg vm_digest "$(sha256sum "$vm_evidence" | awk '{print $1}')" \
  --arg key_vault_hardening_digest "$(
    sha256sum "$key_vault_evidence" | awk '{print $1}'
  )" \
  --arg admin_secret_references_digest "$(
    sha256sum "$admin_secret_evidence" | awk '{print $1}'
  )" \
  '. + {
    status: "provisioned",
    acceptance_complete: true,
    cyclecloud_stack_digest: $stack_digest,
    cyclecloud_vm_digest: $vm_digest,
    key_vault_hardening_digest: $key_vault_hardening_digest,
    admin_secret_references_digest: $admin_secret_references_digest
  }' "$foundation_evidence" >"$foundation_tmp"
mv "$foundation_tmp" "$foundation_evidence"
trap - EXIT
