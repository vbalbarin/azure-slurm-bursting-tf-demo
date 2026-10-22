#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${CHEF_NODE_JSON:?CHEF_NODE_JSON is required}"

chef-client --local-mode \
  --policy-name cyclecloud \
  --policy-group demo \
  --json-attributes "$CHEF_NODE_JSON" \
  --log_level warn
