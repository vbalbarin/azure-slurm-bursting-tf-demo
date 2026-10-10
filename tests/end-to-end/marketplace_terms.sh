#!/usr/bin/env bash
set -euo pipefail

action="${1:-show}"
tfvars_file="${2:-terraform/environments/demo.tfvars}"

case "$action" in
  show|accept) ;;
  *)
    echo "Usage: $0 {show|accept} [demo.tfvars]" >&2
    exit 2
    ;;
esac

for command in az jq terraform; do
  command -v "$command" >/dev/null || {
    echo "Missing required command: $command" >&2
    exit 2
  }
done

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# The export helper emits shell-safe values for human review; suppress them here
# because this command prints only the terms-specific context.
# shellcheck disable=SC1091
source "$script_dir/export_preflight_env.sh" "$tfvars_file" >/dev/null

active_subscription_id="$(az account show --query id --output tsv)"
if [[ "${active_subscription_id,,}" != "${TARGET_SUBSCRIPTION_ID,,}" ]]; then
  echo "Active Azure subscription does not match the subscription in $tfvars_file" >&2
  echo "Active: $active_subscription_id" >&2
  echo "Target: $TARGET_SUBSCRIPTION_ID" >&2
  exit 3
fi

terms_json="$(az vm image terms show --urn "$CYCLECLOUD_URN" --output json)"
jq '{
  urn: $urn,
  subscription_id: $subscription_id,
  accepted,
  license_text_link: .licenseTextLink,
  privacy_policy_link: .privacyPolicyLink,
  marketplace_terms_link: .marketplaceTermsLink,
  retrieve_datetime: .retrieveDatetime
}' --arg urn "$CYCLECLOUD_URN" \
   --arg subscription_id "$TARGET_SUBSCRIPTION_ID" \
   <<<"$terms_json"

if [[ "$action" == "show" ]]; then
  exit 0
fi

if jq -e '.accepted == true' <<<"$terms_json" >/dev/null; then
  echo "Marketplace terms are already accepted for $CYCLECLOUD_URN" >&2
  exit 0
fi

[[ "${ACCEPT_MARKETPLACE_TERMS:-}" == "yes" ]] || {
  echo "Terms were not accepted." >&2
  echo "Review the links above, then rerun with ACCEPT_MARKETPLACE_TERMS=yes and the accept action." >&2
  exit 4
}

az vm image terms accept --urn "$CYCLECLOUD_URN" --output none

az vm image terms show --urn "$CYCLECLOUD_URN" \
  --query '{urn:marketplaceTermsLink,accepted:accepted}' --output json |
  jq -e '.accepted == true' >/dev/null || {
  echo "Marketplace terms acceptance could not be verified" >&2
  exit 5
}

echo "Marketplace terms accepted and verified for $CYCLECLOUD_URN" >&2
