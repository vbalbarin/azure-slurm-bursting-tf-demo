#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat >&2 <<'EOF'
usage: converge_linux_roles.sh --run-context <file> --operation <initial|retry|update|verify-idempotency|inspect|validate-ui-attestation|verify-reboot> [--identity-receipt <file>] [--ui-attestation <file>] [--update-role <cyclecloud|scheduler> --update-payload-dir <directory>]
EOF
}

run_context=
operation=
identity_receipt=
ui_attestation=
update_role=
update_payload_dir=
while (($#)); do
  case "$1" in
    --run-context) run_context="${2:-}"; shift 2 ;;
    --operation) operation="${2:-}"; shift 2 ;;
    --identity-receipt) identity_receipt="${2:-}"; shift 2 ;;
    --ui-attestation) ui_attestation="${2:-}"; shift 2 ;;
    --update-role) update_role="${2:-}"; shift 2 ;;
    --update-payload-dir) update_payload_dir="${2:-}"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done
[[ -f "$run_context" && ! -L "$run_context" ]] || { echo "run context is missing or unsafe" >&2; exit 2; }
case "$operation" in
  initial|retry|update|verify-idempotency|inspect|validate-ui-attestation|verify-reboot) ;;
  *) usage; exit 2 ;;
esac

allowed_context='^(AZURE_SUBSCRIPTION_ID|RESOURCE_GROUP|CYCLECLOUD_VM_NAME|SCHEDULER_VM_NAME|SCHEDULER_MANAGED_IDENTITY_CLIENT_ID|SOURCE_REVISION|CYCLECLOUD_MANIFEST_DIGEST|CYCLECLOUD_SPECIFICATION_DIGEST|SCHEDULER_MANIFEST_DIGEST|SCHEDULER_SPECIFICATION_DIGEST|EVIDENCE_DIR)='
while IFS='=' read -r key value; do
  [[ -z "$key" || "$key" == \#* ]] && continue
  [[ "$key=$value" =~ $allowed_context ]] || { echo "unsupported run-context entry" >&2; exit 2; }
  declare -gx "$key=$value"
done <"$run_context"

for name in SOURCE_REVISION SCHEDULER_SPECIFICATION_DIGEST; do
  [[ -n "${!name:-}" ]] || { echo "$name is required" >&2; exit 2; }
done
[[ "$SOURCE_REVISION" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid source revision" >&2; exit 2; }
[[ "$SCHEDULER_SPECIFICATION_DIGEST" =~ ^[0-9a-f]{64}$ ]] || {
  echo "invalid scheduler specification digest" >&2
  exit 2
}

validate_ui_attestation() {
  [[ -f "$identity_receipt" && -f "$ui_attestation" ]] || {
    echo "identity receipt and UI attestation are required" >&2
    return 1
  }
  python3 - "$identity_receipt" "$ui_attestation" "$SOURCE_REVISION" \
    "$SCHEDULER_SPECIFICATION_DIGEST" <<'PY'
import hashlib
import json
import base64
from pathlib import Path
import re
import struct
import sys

receipt = json.loads(Path(sys.argv[1]).read_text())
attestation = json.loads(Path(sys.argv[2]).read_text())
source_revision, specification_digest = sys.argv[3:]
canonical = dict(receipt)
claimed_digest = canonical.pop("identityReceiptDigest", None)
actual_digest = hashlib.sha256(
    json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode()
).hexdigest()
if claimed_digest != actual_digest:
    raise SystemExit("identity receipt digest mismatch")
if (
    receipt.get("name") != "hpcuser01"
    or receipt.get("uid") != 11200
    or receipt.get("gid") != 11200
    or receipt.get("home") != "/shared/home/hpcuser01"
    or not re.fullmatch(r"ssh-ed25519 [A-Za-z0-9+/]+={0,3}", receipt.get("publicKey", ""))
):
    raise SystemExit("identity receipt has an invalid workload identity")
try:
    key_blob = base64.b64decode(receipt["publicKey"].split()[1], validate=True)
    name_size = struct.unpack(">I", key_blob[:4])[0]
    name_end = 4 + name_size
    key_size = struct.unpack(">I", key_blob[name_end:name_end + 4])[0]
    if (
        key_blob[4:name_end] != b"ssh-ed25519"
        or key_size != 32
        or len(key_blob) != name_end + 4 + key_size
    ):
        raise ValueError
except (ValueError, KeyError, IndexError, struct.error):
    raise SystemExit("identity receipt contains an invalid Ed25519 public key")
if receipt.get("sourceRevision") != source_revision:
    raise SystemExit("identity receipt source revision mismatch")
if receipt.get("specificationDigest") != specification_digest:
    raise SystemExit("identity receipt specification digest mismatch")
required = {
    "schemaVersion": 1,
    "userName": "hpcuser01",
    "superuser": False,
    "nodeAccessEnabled": True,
    "uid": 11200,
    "publicKeyFingerprint": receipt.get("publicKeyFingerprint"),
    "sourceRevision": source_revision,
    "specificationDigest": specification_digest,
    "identityReceiptDigest": claimed_digest,
    "clusterName": "cross-region-demo",
    "clusterPermission": "node-user",
    "result": "accepted",
}
for key, expected in required.items():
    if attestation.get(key) != expected:
        raise SystemExit(f"UI attestation rejected: {key}")
if attestation.get("applicationPasswordDisposition") not in (
    "not-required",
    "force-reset-discarded",
):
    raise SystemExit("UI attestation rejected: password disposition")
if not isinstance(attestation.get("operator"), str) or not attestation["operator"]:
    raise SystemExit("UI attestation rejected: operator")
if not re.fullmatch(
    r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z",
    attestation.get("recordedAt", ""),
):
    raise SystemExit("UI attestation rejected: timestamp")
allowed = {
    "schemaVersion", "operator", "recordedAt", "userName", "superuser",
    "nodeAccessEnabled", "uid", "publicKeyFingerprint", "sourceRevision",
    "specificationDigest", "identityReceiptDigest", "clusterName",
    "clusterPermission", "applicationPasswordDisposition", "result",
}
if set(attestation) != allowed:
    raise SystemExit("UI attestation rejected: unsupported or protected fields")
PY
}

if [[ "$operation" == validate-ui-attestation ]]; then
  validate_ui_attestation
  echo "CycleCloud UI attestation accepted"
  exit 0
fi

for name in AZURE_SUBSCRIPTION_ID RESOURCE_GROUP CYCLECLOUD_VM_NAME \
  SCHEDULER_VM_NAME CYCLECLOUD_MANIFEST_DIGEST \
  CYCLECLOUD_SPECIFICATION_DIGEST SCHEDULER_MANIFEST_DIGEST EVIDENCE_DIR; do
  [[ -n "${!name:-}" ]] || { echo "$name is required" >&2; exit 2; }
done
for name in CYCLECLOUD_MANIFEST_DIGEST CYCLECLOUD_SPECIFICATION_DIGEST \
  SCHEDULER_MANIFEST_DIGEST; do
  [[ "${!name}" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid governed digest" >&2; exit 2; }
done
for command in az jq python3 sha256sum timeout; do
  command -v "$command" >/dev/null || { echo "missing required command: $command" >&2; exit 2; }
done
install -d -m 0700 "$EVIDENCE_DIR"

run_command() {
  local vm_name="$1"
  local script="$2"
  timeout 55 az vm run-command invoke \
    --subscription "$AZURE_SUBSCRIPTION_ID" \
    --resource-group "$RESOURCE_GROUP" \
    --name "$vm_name" \
    --command-id RunShellScript \
    --scripts "$script" \
    --only-show-errors \
    --output json
}

inspect_state() {
  local role="$1"
  local vm_name="$2"
  local output="$3"
  local response message
  response="$(run_command "$vm_name" "cat /var/lib/slurm-demo/$role/state.json")" || {
    echo "$role state inspection failed or exceeded 55 seconds" >&2
    return 1
  }
  message="$(jq -er '.value[0].message' <<<"$response")"
  python3 - "$role" "$output" "$message" <<'PY'
import json
from pathlib import Path
import re
import sys

role, output, message = sys.argv[1:]
start = message.find("{")
end = message.rfind("}")
if start < 0 or end < start:
    raise SystemExit("Run Command did not return JSON state")
state = json.loads(message[start:end + 1])
required = {
    "schemaVersion", "role", "state", "sourceRevision", "manifestDigest",
    "specificationDigest", "attempt", "updatedAt", "detailCode",
}
if set(state) != required or state["schemaVersion"] != 1 or state["role"] != role:
    raise SystemExit("remote state does not satisfy the bounded state contract")
if not re.fullmatch(r"[0-9a-f]{40}", state["sourceRevision"]):
    raise SystemExit("remote state source revision is invalid")
for key in ("manifestDigest", "specificationDigest"):
    if not re.fullmatch(r"[0-9a-f]{64}", state[key]):
        raise SystemExit("remote state digest is invalid")
allowed_states = {
    "staging", "environment_ready", "waiting_dependencies", "converging",
    "failed_retryable", "replacement_required", "converged",
    "verifying_idempotency", "idempotency_verified", "update_authorized", "failed",
}
if state["state"] not in allowed_states:
    raise SystemExit("remote state value is invalid")
if type(state["attempt"]) is not int or not 0 <= state["attempt"] <= 2:
    raise SystemExit("remote state attempt is invalid")
if not re.fullmatch(
    r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})",
    state["updatedAt"],
):
    raise SystemExit("remote state timestamp is invalid")
if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", state["detailCode"]):
    raise SystemExit("remote state detail code is invalid")
Path(output).write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")
PY
}

cyclecloud_state="$EVIDENCE_DIR/cyclecloud-state.json"
scheduler_state="$EVIDENCE_DIR/scheduler-state.json"
inspect_state cyclecloud "$CYCLECLOUD_VM_NAME" "$cyclecloud_state"
inspect_state scheduler "$SCHEDULER_VM_NAME" "$scheduler_state"

verify_state_identity() {
  local state_file="$1" manifest_digest="$2" specification_digest="$3"
  jq -e --arg source "$SOURCE_REVISION" --arg manifest "$manifest_digest" \
    --arg specification "$specification_digest" '
      .sourceRevision == $source and .manifestDigest == $manifest and
      .specificationDigest == $specification
    ' "$state_file" >/dev/null
}
if [[ "$operation" != update ]]; then
  verify_state_identity "$cyclecloud_state" "$CYCLECLOUD_MANIFEST_DIGEST" \
    "$CYCLECLOUD_SPECIFICATION_DIGEST"
  verify_state_identity "$scheduler_state" "$SCHEDULER_MANIFEST_DIGEST" \
    "$SCHEDULER_SPECIFICATION_DIGEST"
fi

if [[ "$operation" == inspect ]]; then
  exit 0
fi

if [[ "$operation" == verify-reboot ]]; then
  capture_reboot_receipt() {
    local role="$1" vm_name="$2" output="$3" script response message
    # These commands expand only on the remote VM.
    # shellcheck disable=SC2016
    if [[ "$role" == cyclecloud ]]; then
      script='set -euo pipefail; cert=$(timeout 5 openssl s_client -connect 127.0.0.1:443 </dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256 | cut -d= -f2); clusters=$(cyclecloud cluster list --output json | jq '"'"'[.[] | select(.Name == "cross-region-demo")] | length'"'"'); evidence=$(find /var/lib/slurm-demo/cyclecloud/evidence -maxdepth 1 -type f -printf '"'"'%f\n'"'"' | sort | sha256sum | awk '"'"'{print $1}'"'"'); jq -cn --arg cert "$cert" --arg evidence "$evidence" --argjson clusters "$clusters" '"'"'{role:"cyclecloud",publicCredentialFingerprint:$cert,clusterCount:$clusters,evidenceSetDigest:$evidence,explicitPolicyOnly:true}'"'"''
    else
      script='set -euo pipefail; key=$(ssh-keygen -E sha256 -lf /shared/home/hpcuser01/.ssh/id_ed25519.pub | awk '"'"'{print $2}'"'"'); evidence=$(find /var/lib/slurm-demo/scheduler/evidence -maxdepth 1 -type f -printf '"'"'%f\n'"'"' | sort | sha256sum | awk '"'"'{print $1}'"'"'); if systemctl list-timers --all --no-legend | grep -Eq '"'"'slurm-demo|chef|converge'"'"'; then policy=false; else policy=true; fi; jq -cn --arg key "$key" --arg evidence "$evidence" --argjson policy "$policy" '"'"'{role:"scheduler",publicCredentialFingerprint:$key,clusterCount:0,evidenceSetDigest:$evidence,explicitPolicyOnly:$policy}'"'"''
    fi
    response="$(run_command "$vm_name" "$script")"
    message="$(jq -er '.value[0].message' <<<"$response")"
    python3 - "$message" "$output" <<'PY'
import json
from pathlib import Path
import sys

message, output = sys.argv[1:]
start, end = message.find("{"), message.rfind("}")
if start < 0 or end < start:
    raise SystemExit("reboot receipt is missing")
document = json.loads(message[start:end + 1])
required = {
    "role", "publicCredentialFingerprint", "clusterCount",
    "evidenceSetDigest", "explicitPolicyOnly",
}
if set(document) != required or document["explicitPolicyOnly"] is not True:
    raise SystemExit("reboot receipt is invalid")
if not document["publicCredentialFingerprint"]:
    raise SystemExit("public credential fingerprint is missing")
if document["role"] == "cyclecloud" and document["clusterCount"] != 1:
    raise SystemExit("CycleCloud cluster count changed")
Path(output).write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
PY
  }

  cyclecloud_reboot="$EVIDENCE_DIR/cyclecloud-reboot-receipt.json"
  scheduler_reboot="$EVIDENCE_DIR/scheduler-reboot-receipt.json"
  capture_reboot_receipt cyclecloud "$CYCLECLOUD_VM_NAME" "$cyclecloud_reboot"
  capture_reboot_receipt scheduler "$SCHEDULER_VM_NAME" "$scheduler_reboot"
  baseline_dir="$EVIDENCE_DIR/reboot-baseline"
  if [[ ! -d "$baseline_dir" ]]; then
    install -d -m 0700 "$baseline_dir"
    install -m 0600 "$cyclecloud_state" "$baseline_dir/cyclecloud-state.json"
    install -m 0600 "$scheduler_state" "$baseline_dir/scheduler-state.json"
    install -m 0600 "$cyclecloud_reboot" "$baseline_dir/cyclecloud-receipt.json"
    install -m 0600 "$scheduler_reboot" "$baseline_dir/scheduler-receipt.json"
    echo "persistent VM reboot baseline recorded"
    exit 0
  fi
  python3 - \
    "$baseline_dir/cyclecloud-state.json" "$cyclecloud_state" \
    "$baseline_dir/scheduler-state.json" "$scheduler_state" \
    "$baseline_dir/cyclecloud-receipt.json" "$cyclecloud_reboot" \
    "$baseline_dir/scheduler-receipt.json" "$scheduler_reboot" <<'PY'
import json
import sys

for index in range(1, len(sys.argv), 2):
    before, after = (
        json.load(open(path, encoding="utf-8"))
        for path in sys.argv[index:index + 2]
    )
    if "state" in before:
        for key in (
            "sourceRevision", "manifestDigest", "specificationDigest",
            "attempt", "state",
        ):
            if before.get(key) != after.get(key):
                raise SystemExit(f"persistent VM reboot changed {key}")
    elif before != after:
        raise SystemExit("persistent VM reboot changed credentials, cluster count, evidence, or policy behavior")
PY
  echo "persistent VM reboot evidence is unchanged"
  exit 0
fi

case "$operation" in
  initial)
    jq -e '.state == "converged" or .state == "idempotency_verified"' \
      "$cyclecloud_state" >/dev/null || { echo "CycleCloud dependency is not converged" >&2; exit 1; }
    jq -e '.state == "environment_ready" or .state == "waiting_dependencies"' \
      "$scheduler_state" >/dev/null || { echo "scheduler is not ready for initial dispatch" >&2; exit 1; }
    ;;
  retry)
    jq -e '.state == "failed_retryable" and .attempt == 1' "$scheduler_state" >/dev/null ||
      { echo "scheduler retry is not authorized" >&2; exit 1; }
    ;;
  verify-idempotency)
    jq -e '.state == "converged" or .state == "idempotency_verified"' \
      "$cyclecloud_state" >/dev/null || { echo "CycleCloud is not converged" >&2; exit 1; }
    jq -e '.state == "converged" or .state == "idempotency_verified"' \
      "$scheduler_state" >/dev/null || { echo "scheduler is not converged" >&2; exit 1; }
    ;;
  update)
    [[ "$update_role" == cyclecloud || "$update_role" == scheduler ]] || {
      echo "update role must be cyclecloud or scheduler" >&2
      exit 2
    }
    [[ -d "$update_payload_dir" && ! -L "$update_payload_dir" ]] || {
      echo "approved update payload directory is missing or unsafe" >&2
      exit 2
    }
    ;;
esac

stage_update() {
  local role="$1" vm_name="$2" policy="$1"
  [[ "$role" != scheduler ]] || policy=slurm
  local archive="$update_payload_dir/$role.tgz"
  local manifest="$update_payload_dir/$role.manifest.json"
  local specification="$update_payload_dir/$role.node-specification.json"
  local lock="$update_payload_dir/$policy.lock.json"
  local expected_manifest expected_specification
  expected_manifest="$CYCLECLOUD_MANIFEST_DIGEST"
  expected_specification="$CYCLECLOUD_SPECIFICATION_DIGEST"
  if [[ "$role" == scheduler ]]; then
    expected_manifest="$SCHEDULER_MANIFEST_DIGEST"
    expected_specification="$SCHEDULER_SPECIFICATION_DIGEST"
  fi
  update_validation="$(
    python3 - "$role" "$policy" "$archive" "$manifest" "$specification" "$lock" \
      "$SOURCE_REVISION" "$expected_manifest" "$expected_specification" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

role, policy = sys.argv[1:3]
archive_path, manifest_path, specification_path, lock_path = map(Path, sys.argv[3:7])
source, expected_manifest, expected_specification = sys.argv[7:]
for path in (archive_path, manifest_path, specification_path, lock_path):
    if not path.is_file() or path.is_symlink():
        raise SystemExit("approved update input is missing or unsafe")
manifest = json.loads(manifest_path.read_text())
specification = json.loads(specification_path.read_text())
lock = json.loads(lock_path.read_text())

def canonical(document, field):
    value = dict(document)
    value.pop(field, None)
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()

artifact = [
    item for item in manifest.get("artifacts", [])
    if item.get("kind") == "policy"
]
checks = (
    manifest.get("role") == role,
    manifest.get("policyName") == policy,
    specification.get("role") == role,
    manifest.get("sourceRevision") == source == specification.get("sourceRevision"),
    manifest.get("manifestDigest") == expected_manifest
    == canonical(manifest, "manifestDigest"),
    specification.get("specificationDigest") == expected_specification
    == canonical(specification, "specificationDigest"),
    lock.get("revision_id") == manifest.get("policyRevision"),
    hashlib.sha256(lock_path.read_bytes()).hexdigest()
    == manifest.get("policyLockSha256"),
    len(artifact) == 1
    and hashlib.sha256(archive_path.read_bytes()).hexdigest()
    == artifact[0].get("sha256"),
)
if not all(checks):
    raise SystemExit("approved update payload validation failed")
print(
    manifest["manifestDigest"],
    specification["specificationDigest"],
)
PY
  )"
  read -r update_manifest update_specification \
    <<<"$update_validation"

  local archive_b64 manifest_b64 specification_b64 lock_b64
  archive_b64="$(base64 -w0 "$archive")"
  manifest_b64="$(base64 -w0 "$manifest")"
  specification_b64="$(base64 -w0 "$specification")"
  lock_b64="$(base64 -w0 "$lock")"
  local remote_state_role="$role"
  [[ "$role" != scheduler ]] || remote_state_role=scheduler
  local remote_script
  remote_script="set -euo pipefail; umask 077; d=/run/slurm-demo/update-$role; rm -rf \"\$d\"; install -d -m 0700 \"\$d\"; trap 'rm -rf \"\$d\"' EXIT; previous=\$(readlink -f /opt/slurm-demo/current); cp /var/lib/slurm-demo/$remote_state_role/state.json /var/lib/slurm-demo/$remote_state_role/update-previous-state.json; chmod 0600 /var/lib/slurm-demo/$remote_state_role/update-previous-state.json; printf '%s' '$archive_b64' | base64 -d >\"\$d/$role.tgz\"; printf '%s' '$manifest_b64' | base64 -d >\"\$d/manifest.json\"; printf '%s' '$specification_b64' | base64 -d >\"\$d/node-specification.json\"; printf '%s' '$lock_b64' | base64 -d >\"\$d/$policy.lock.json\"; tar --extract --to-stdout --gzip --file \"\$d/$role.tgz\" chef/bootstrap/linux.sh >\"\$d/bootstrap.sh\"; chmod 0700 \"\$d/bootstrap.sh\"; python3 /opt/slurm-demo/current/chef/bin/convergence_state.py --state-dir /var/lib/slurm-demo transition --role '$remote_state_role' --source-revision '$SOURCE_REVISION' --manifest-digest '$update_manifest' --specification-digest '$update_specification' --state update_authorized --attempt 0 --detail-code approved_update; CHEF_POLICY_NAME='$policy' CHEF_POLICY_ARCHIVE_PATH=\"\$d/$role.tgz\" CHEF_MANIFEST_PATH=\"\$d/manifest.json\" CHEF_NODE_SPECIFICATION_PATH=\"\$d/node-specification.json\" \"\$d/bootstrap.sh\"; printf '%s' \"\$previous\" >/var/lib/slurm-demo/$remote_state_role/update-previous-release"
  update_response="$(run_command "$vm_name" "$remote_script")" || {
    echo "$role update staging failed" >&2
    exit 1
  }
  printf '%s\n' "$update_response" >"$EVIDENCE_DIR/$role-update-staging-run-command.json"
}

if [[ "$operation" == update ]]; then
  if [[ "$update_role" == cyclecloud ]]; then
    stage_update cyclecloud "$CYCLECLOUD_VM_NAME"
    update_previous_release="$(jq -er '.value[0].message | capture(\"(?<path>/opt/slurm-demo/releases/[0-9a-f]{64})\").path' <<<"$(
      run_command "$CYCLECLOUD_VM_NAME" "cat /var/lib/slurm-demo/cyclecloud/update-previous-release"
    )")"
    update_script="CONVERGENCE_OPERATION=update SLURM_DEMO_PREVIOUS_RELEASE='$update_previous_release' SLURM_DEMO_PREVIOUS_STATE=/var/lib/slurm-demo/cyclecloud/update-previous-state.json /opt/slurm-demo/current/chef/bin/converge-cyclecloud.sh"
    run_command "$CYCLECLOUD_VM_NAME" "$update_script" \
      >"$EVIDENCE_DIR/cyclecloud-update-run-command.json" || {
        echo "CycleCloud update convergence failed and restored the prior release" >&2
        exit 1
      }
    exit 0
  fi
  stage_update scheduler "$SCHEDULER_VM_NAME"
fi

cyclecloud_receipt_digest="$(sha256sum "$cyclecloud_state" | awk '{print $1}')"
scheduler_environment_digest="$(sha256sum "$scheduler_state" | awk '{print $1}')"

[[ -n "${SCHEDULER_MANAGED_IDENTITY_CLIENT_ID:-}" ]] || {
  echo "scheduler managed identity client ID is required" >&2
  exit 2
}
# The single-quoted variables expand on the remote VM, not in this dispatcher.
# shellcheck disable=SC2016
secret_probe='set -euo pipefail; umask 077; p=/run/slurm-demo/secret-access-probe; trap '"'"'rm -f "$p"'"'"' EXIT; spec=/opt/slurm-demo/current/node-specification.json; vault=$(python3 -c '"'"'import json; print(json.load(open("'"'"'$spec'"'"'"))["secretReferences"]["vaultUri"])'"'"'); name=$(python3 -c '"'"'import json; print(json.load(open("'"'"'$spec'"'"'"))["secretReferences"]["cyclecloudAdminPassword"])'"'"'); python3 /opt/slurm-demo/current/chef/bin/retrieve-key-vault-secret.py --client-id '"$SCHEDULER_MANAGED_IDENTITY_CLIENT_ID"' --vault-uri "$vault" --secret-name "$name" --output "$p"; test "$(stat -c %a "$p")" = 600; echo secret-access-passed'
probe_response="$(run_command "$SCHEDULER_VM_NAME" "$secret_probe")" || {
  echo "scheduler secret-access gate failed" >&2
  exit 1
}
[[ "$(jq -r '.value[0].message' <<<"$probe_response")" == *secret-access-passed* ]] || {
  echo "scheduler secret-access gate returned no receipt" >&2
  exit 1
}
secret_access_digest="$(printf '%s' "$SCHEDULER_SPECIFICATION_DIGEST:secret-access-passed" | sha256sum | awk '{print $1}')"

authorization="$EVIDENCE_DIR/scheduler-authorization.json"
python3 - "$authorization" "$operation" "$SOURCE_REVISION" \
  "$SCHEDULER_MANIFEST_DIGEST" "$SCHEDULER_SPECIFICATION_DIGEST" \
  "$cyclecloud_receipt_digest" "$scheduler_environment_digest" \
  "$secret_access_digest" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

path, operation, source, manifest, specification, cyclecloud, environment, secret = sys.argv[1:]
document = {
    "schemaVersion": 1,
    "operation": operation,
    "sourceRevision": source,
    "manifestDigest": manifest,
    "specificationDigest": specification,
    "dependencyReceipts": [
        {"name": "cyclecloud", "digest": cyclecloud, "result": "passed"},
        {"name": "scheduler-environment", "digest": environment, "result": "passed"},
        {"name": "secret-access", "digest": secret, "result": "passed"},
    ],
}
canonical = json.dumps(document, sort_keys=True, separators=(",", ":")).encode()
document["authorizationDigest"] = hashlib.sha256(canonical).hexdigest()
Path(path).write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
PY
chmod 0600 "$authorization"

authorization_base64="$(base64 -w0 "$authorization")"
update_environment=
if [[ "$operation" == update ]]; then
  update_environment="SLURM_DEMO_PREVIOUS_RELEASE=\$(cat /var/lib/slurm-demo/scheduler/update-previous-release) SLURM_DEMO_PREVIOUS_STATE=/var/lib/slurm-demo/scheduler/update-previous-state.json"
fi
dispatch_script="set -euo pipefail; umask 077; install -d -m 0700 /run/slurm-demo; printf '%s' '$authorization_base64' | base64 -d > /run/slurm-demo/authorization.json; chmod 0600 /run/slurm-demo/authorization.json; $update_environment AUTHORIZATION_RECEIPT=/run/slurm-demo/authorization.json SCHEDULER_MANAGED_IDENTITY_CLIENT_ID='$SCHEDULER_MANAGED_IDENTITY_CLIENT_ID' /opt/slurm-demo/current/chef/bin/converge-scheduler.sh"
dispatch_response="$(run_command "$SCHEDULER_VM_NAME" "$dispatch_script")" || {
  echo "scheduler convergence dispatch failed" >&2
  exit 1
}
printf '%s\n' "$dispatch_response" >"$EVIDENCE_DIR/scheduler-run-command.json"

identity_response="$(run_command "$SCHEDULER_VM_NAME" \
  "/opt/slurm-demo/current/chef/bin/publish-hpc-user-receipt.sh --source-revision '$SOURCE_REVISION' --specification-digest '$SCHEDULER_SPECIFICATION_DIGEST' --output /var/lib/slurm-demo/scheduler/hpcuser01-public-identity.json && cat /var/lib/slurm-demo/scheduler/hpcuser01-public-identity.json")"
identity_message="$(jq -er '.value[0].message' <<<"$identity_response")"
python3 - "$identity_message" "$EVIDENCE_DIR/hpc-user-receipt.json" <<'PY'
import json
from pathlib import Path
import sys
message, output = sys.argv[1:]
document = json.loads(message[message.find("{"):message.rfind("}") + 1])
Path(output).write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
PY

if [[ -n "$ui_attestation" ]]; then
  identity_receipt="$EVIDENCE_DIR/hpc-user-receipt.json"
  validate_ui_attestation
else
  echo "Scheduler converged; burst dispatch remains blocked pending the supported CycleCloud UI attestation"
fi
