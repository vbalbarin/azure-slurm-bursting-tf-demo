#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${WORKSPACE_ID:?WORKSPACE_ID is required}"
: "${EVIDENCE_DIR:?EVIDENCE_DIR is required}"
: "${PLAN_REFERENCE_FILE:?PLAN_REFERENCE_FILE is required}"
: "${VALIDATION_RESULTS_FILE:?VALIDATION_RESULTS_FILE is required}"
mkdir -p "$EVIDENCE_DIR"

query() {
  local name="$1" expression="$2"
  az monitor log-analytics query --workspace "$WORKSPACE_ID" \
    --analytics-query "$expression" --timespan P90D --output json \
    >"$EVIDENCE_DIR/$name.json"
}

query access 'AzureActivity | where TimeGenerated > ago(90d) | where OperationNameValue has_any ("VAULTS", "BASTION") | project TimeGenerated, Caller, OperationNameValue, ActivityStatusValue'
query configuration 'Syslog | where TimeGenerated > ago(90d) | where ProcessName has_any ("chef-client", "cyclecloud", "slurmctld") | project TimeGenerated, Computer, ProcessName, SeverityLevel'
query cluster 'AzureActivity | where TimeGenerated > ago(90d) | where ResourceProviderValue =~ "MICROSOFT.COMPUTE" | project TimeGenerated, Resource, OperationNameValue, ActivityStatusValue'

if grep -R -Eqi '(password|private[_-]?key|secret)[[:space:]]*[:=][[:space:]]*[^"*{]' "$EVIDENCE_DIR"; then
  echo "Potential secret value found in audit evidence" >&2
  exit 3
fi

jq -n \
  --argjson retention_days 90 \
  --slurpfile validation_results "$VALIDATION_RESULTS_FILE" \
  --slurpfile plan_reference "$PLAN_REFERENCE_FILE" \
  --slurpfile access "$EVIDENCE_DIR/access.json" \
  --slurpfile configuration "$EVIDENCE_DIR/configuration.json" \
  --slurpfile cluster "$EVIDENCE_DIR/cluster.json" \
  '{retention_days:$retention_days,validation_results:$validation_results[0],plan_reference:$plan_reference[0],events:{access:$access[0],configuration:$configuration[0],cluster:$cluster[0]}}' \
  >"$EVIDENCE_DIR/audit-evidence.json"
