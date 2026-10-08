#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${CHEF_POLICY_NAME:?CHEF_POLICY_NAME is required}"
: "${CHEF_POLICY_ARCHIVE_URI:?CHEF_POLICY_ARCHIVE_URI is required}"

case "$CHEF_POLICY_NAME" in
  cyclecloud|slurm) ;;
  *) echo "Unsupported Chef policy" >&2; exit 2 ;;
esac

curl --fail --silent --show-error --proto '=https' --tlsv1.2 \
  "$CHEF_POLICY_ARCHIVE_URI/$CHEF_POLICY_NAME.tgz" \
  --output "/var/tmp/$CHEF_POLICY_NAME.tgz"
install -d -m 0700 "/var/chef/$CHEF_POLICY_NAME"
tar --extract --gzip --file "/var/tmp/$CHEF_POLICY_NAME.tgz" \
  --directory "/var/chef/$CHEF_POLICY_NAME"
rm -f "/var/tmp/$CHEF_POLICY_NAME.tgz"
exec chef-client --local-mode --policy-name "$CHEF_POLICY_NAME" \
  --policy-group demo --config-option "cookbook_path=/var/chef/$CHEF_POLICY_NAME/cookbooks"
