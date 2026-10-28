#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077

release_root="${SLURM_DEMO_RELEASE_ROOT:-/opt/slurm-demo/current}"
state_root="${SLURM_DEMO_STATE_ROOT:-/var/lib/slurm-demo}"
authorization_receipt="${AUTHORIZATION_RECEIPT:-/run/slurm-demo/authorization.json}"
managed_identity_client_id="${SCHEDULER_MANAGED_IDENTITY_CLIENT_ID:-}"
manifest="$release_root/manifest.json"
specification="$release_root/node-specification.json"
lock="$release_root/chef/policyfiles/slurm.lock.json"
previous_release="${SLURM_DEMO_PREVIOUS_RELEASE:-}"
previous_state="${SLURM_DEMO_PREVIOUS_STATE:-}"

[[ "$(id -u)" -eq 0 ]] || { echo "scheduler convergence requires root" >&2; exit 1; }
install -d -m 0700 "$state_root/scheduler"
exec 9>"$state_root/scheduler/wrapper.lock"
flock -n 9 || { echo "scheduler convergence is already active" >&2; exit 75; }
[[ -f "$authorization_receipt" && ! -L "$authorization_receipt" ]] || {
  echo "governed authorization receipt is required" >&2
  exit 1
}
[[ -n "$managed_identity_client_id" ]] || {
  echo "scheduler managed identity client ID is required" >&2
  exit 1
}

runtime_dir=/run/slurm-demo
install -d -m 0700 "$runtime_dir"
secret_file="$runtime_dir/cyclecloud-password.$$"
attributes_file="$runtime_dir/chef-attributes.$$"
chef_log="$runtime_dir/chef-output.$$"
chef_config="$runtime_dir/chef-client.$$.rb"
chef_cache="$runtime_dir/chef-cache.$$"
autoscale_candidate="$runtime_dir/autoscale.$$"
partitions_candidate="$runtime_dir/azure.conf.$$"
cleanup() {
  rm -f "$secret_file" "$attributes_file" "$chef_log" "$autoscale_candidate" \
    "$partitions_candidate" "$authorization_receipt" "$chef_config"
  rm -rf "$chef_cache"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

restore_previous_release() {
  [[ "${operation:-}" == update ]] || return 0
  [[ -d "$previous_release" && -f "$previous_state" ]] || {
    echo "scheduler update cannot restore the prior release" >&2
    return 1
  }
  python3 - "$previous_release" "$previous_state" "$release_root" \
    "$state_root/scheduler/state.json" <<'PY'
import os
from pathlib import Path
import shutil
import sys

previous_release, previous_state, current, state = map(Path, sys.argv[1:])
temporary = current.parent / ".current.rollback"
temporary.unlink(missing_ok=True)
temporary.symlink_to(previous_release)
os.replace(temporary, current)
state_temporary = state.with_name(f".{state.name}.rollback")
shutil.copyfile(previous_state, state_temporary)
state_temporary.chmod(0o600)
os.replace(state_temporary, state)
PY
}

validation="$(
  python3 - "$manifest" "$specification" "$lock" "$authorization_receipt" <<'PY'
import hashlib
import json
from pathlib import Path
import re
import sys

manifest_path, specification_path, lock_path, authorization_path = map(Path, sys.argv[1:])
for path in (manifest_path, specification_path, lock_path, authorization_path):
    if not path.is_file() or path.is_symlink():
        raise SystemExit("required convergence input is missing or unsafe")
manifest = json.loads(manifest_path.read_text())
specification = json.loads(specification_path.read_text())
lock = json.loads(lock_path.read_text())
authorization = json.loads(authorization_path.read_text())

def canonical_digest(document, field):
    value = dict(document)
    value.pop(field, None)
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()

if manifest.get("role") != "scheduler" or specification.get("role") != "scheduler":
    raise SystemExit("scheduler role input mismatch")
if manifest.get("manifestDigest") != canonical_digest(manifest, "manifestDigest"):
    raise SystemExit("manifest digest mismatch")
if specification.get("specificationDigest") != canonical_digest(
    specification, "specificationDigest"
):
    raise SystemExit("specification digest mismatch")
if manifest.get("sourceRevision") != specification.get("sourceRevision"):
    raise SystemExit("source revision mismatch")
if lock.get("revision_id") != manifest.get("policyRevision"):
    raise SystemExit("policy revision mismatch")
if lock.get("run_list") != ["recipe[slurm_scheduler::default]"]:
    raise SystemExit("policy run list mismatch")
if hashlib.sha256(lock_path.read_bytes()).hexdigest() != manifest.get("policyLockSha256"):
    raise SystemExit("policy lock digest mismatch")
if authorization.get("schemaVersion") != 1:
    raise SystemExit("authorization schema mismatch")
authorization_digest = authorization.pop("authorizationDigest", None)
if authorization_digest != canonical_digest(authorization, "authorizationDigest"):
    raise SystemExit("authorization digest mismatch")
for key, expected in (
    ("sourceRevision", manifest["sourceRevision"]),
    ("manifestDigest", manifest["manifestDigest"]),
    ("specificationDigest", specification["specificationDigest"]),
):
    if authorization.get(key) != expected:
        raise SystemExit("authorization input mismatch")
operation = authorization.get("operation")
if operation not in ("initial", "retry", "update", "verify-idempotency"):
    raise SystemExit("unauthorized scheduler operation")
receipts = authorization.get("dependencyReceipts")
if not isinstance(receipts, list) or {
    item.get("name") for item in receipts if isinstance(item, dict) and item.get("result") == "passed"
} != {"cyclecloud", "scheduler-environment", "secret-access"}:
    raise SystemExit("dependency authorization is incomplete")
for item in receipts:
    if not re.fullmatch(r"[0-9a-f]{64}", item.get("digest", "")):
        raise SystemExit("invalid dependency receipt digest")
print(
    manifest["sourceRevision"],
    manifest["manifestDigest"],
    specification["specificationDigest"],
    manifest["policyRevision"],
    manifest["policyLockSha256"],
    operation,
    specification["secretReferences"]["vaultUri"],
    specification["secretReferences"]["cyclecloudAdminPassword"],
    specification["cyclecloudUrl"],
    specification["clusterName"],
    lock["run_list"][0],
    *[f'{item["name"]}={item["digest"]}' for item in receipts],
)
PY
)"
read -r source_revision manifest_digest specification_digest policy_revision \
  policy_lock_sha256 operation vault_uri secret_name cyclecloud_url cluster_name \
  chef_run_list cyclecloud_receipt environment_receipt secret_access_receipt <<<"$validation"

attempt=1
transition_state=converging
if [[ "$operation" == retry ]]; then
  attempt=2
elif [[ "$operation" == update ]]; then
  [[ -d "$previous_release" && -f "$previous_state" ]] || {
    echo "scheduler update requires the prior release and state snapshot" >&2
    exit 2
  }
elif [[ "$operation" == verify-idempotency ]]; then
  transition_state=verifying_idempotency
  current_attempt="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["attempt"])' "$state_root/scheduler/state.json")"
  attempt="$current_attempt"
fi

python3 "$release_root/chef/bin/convergence_state.py" --state-dir "$state_root" transition \
  --role scheduler --source-revision "$source_revision" \
  --manifest-digest "$manifest_digest" --specification-digest "$specification_digest" \
  --state "$transition_state" --attempt "$attempt" --detail-code authorized

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
failure_stage=secret_retrieval
record_early_failure() {
  local status=$?
  trap - ERR
  cleanup
  local failed_state=failed_retryable
  [[ "$attempt" -eq 1 ]] || failed_state=replacement_required
  [[ "$operation" != verify-idempotency ]] || failed_state=failed
  local finished_at
  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  python3 "$release_root/chef/bin/convergence_state.py" --state-dir "$state_root" transition \
    --role scheduler --source-revision "$source_revision" \
    --manifest-digest "$manifest_digest" --specification-digest "$specification_digest" \
    --state "$failed_state" --attempt "$attempt" --detail-code "$failure_stage" || true
  python3 "$release_root/chef/bin/convergence_state.py" --state-dir "$state_root" record-evidence \
    --role scheduler --source-revision "$source_revision" \
    --manifest-digest "$manifest_digest" --specification-digest "$specification_digest" \
    --policy-revision "$policy_revision" --policy-lock-sha256 "$policy_lock_sha256" \
    --attempt "$attempt" --result failed --state "$failed_state" \
    --started-at "$started_at" --finished-at "$finished_at" \
    --dependency-receipt "$cyclecloud_receipt" \
    --dependency-receipt "$environment_receipt" \
    --dependency-receipt "$secret_access_receipt" \
    --cleanup-verified --failure-stage "$failure_stage" || true
  restore_previous_release || true
  exit "$status"
}
trap record_early_failure ERR
python3 - "$specification" "$attributes_file" false <<'PY'
import json
from pathlib import Path
import sys

specification = json.loads(Path(sys.argv[1]).read_text())
integration_ready = sys.argv[3] == "true"
attributes = {
    "slurm": {
        "version": "24.11.5",
        "project_version": "4.0.11",
        "cluster_name": specification["clusterName"],
        "scheduler_private_address": specification["schedulerPrivateAddress"],
        "burst_cidr": specification["burstCidr"],
        "cyclecloud_url": specification["cyclecloudUrl"],
        "uid": specification["slurmIdentity"]["uid"],
        "gid": specification["slurmIdentity"]["gid"],
        "integration_ready": integration_ready,
    },
    "munge": specification["mungeIdentity"],
    "demo_user": {
        "name": specification["hpcUser"]["name"],
        "uid_gid": specification["hpcUser"]["uid"],
        "home": specification["hpcUser"]["home"],
    },
}
Path(sys.argv[2]).write_text(json.dumps(attributes))
PY
chmod 0600 "$attributes_file"
install -d -m 0700 "$chef_cache"
printf '%s\n' \
  "chef_repo_path \"$release_root\"" \
  "cookbook_path [\"$release_root/chef/cookbooks\"]" \
  "file_cache_path \"$chef_cache\"" >"$chef_config"
chmod 0600 "$chef_config"

failure_stage=chef_installation
(
  cd "$release_root"
  CHEF_LICENSE=accept-no-persist chef-client --local-mode \
    --config "$chef_config" \
    --override-runlist "$chef_run_list" \
    --json-attributes "$attributes_file" --log_level info
) >"$chef_log" 2>&1

failure_stage=protected_process_visibility
grep -Eq '[[:space:]]/proc[[:space:]].*[,(]hidepid=2([,[:space:]]|$)' /proc/mounts || {
  echo "protected process visibility is required for azslurm initialization" >&2
  false
}

failure_stage=secret_retrieval
python3 "$release_root/chef/bin/retrieve-key-vault-secret.py" \
  --client-id "$managed_identity_client_id" --vault-uri "$vault_uri" \
  --secret-name "$secret_name" --output "$secret_file"
if [[ "$(stat -c %a "$secret_file")" != 600 ]]; then
  echo "temporary credential permissions are invalid" >&2
  false
fi

failure_stage=azslurm_initialization
autoscale_config=/opt/azurehpc/slurm/autoscale.json
if [[ ! -f "$autoscale_config" ]]; then
  (
    set +x
    umask 077
    azslurm initconfig \
      --url "$cyclecloud_url" --cluster-name "$cluster_name" \
      --username hpcadmin --password "$(cat "$secret_file")" \
      --config-dir "/sched/$cluster_name" \
      --accounting-subscription-id unused \
      --default-resource '{"select":{},"name":"slurm_gpus","value":"node.gpu_count"}' \
      --cost-cache-root /opt/azurehpc/slurm/.cache \
      >"$autoscale_candidate"
  )
  install -o root -g slurm -m 0600 "$autoscale_candidate" "$autoscale_config"
  rm -f "$autoscale_candidate"
fi
azslurm partitions >"$partitions_candidate"
install -o root -g slurm -m 0640 "$partitions_candidate" /sched/azure.conf
rm -f "$partitions_candidate"
rm -f "$secret_file"

python3 - "$attributes_file" <<'PY'
import json
from pathlib import Path
import sys

path = Path(sys.argv[1])
attributes = json.loads(path.read_text())
attributes["slurm"]["integration_ready"] = True
path.write_text(json.dumps(attributes))
PY

failure_stage=chef_convergence
set +e
(
  cd "$release_root"
  CHEF_LICENSE=accept-no-persist chef-client --local-mode \
    --config "$chef_config" \
    --override-runlist "$chef_run_list" \
    --json-attributes "$attributes_file" --log_level info
) >>"$chef_log" 2>&1
chef_status=$?
set -e
updated_resources=
if [[ "$chef_status" -eq 0 ]]; then
  updated_resources="$(
    python3 - "$chef_log" <<'PY'
from pathlib import Path
import re
import sys

matches = re.findall(
    r"Chef Infra Client finished, (\d+)/\d+ resources updated",
    Path(sys.argv[1]).read_text(),
)
if len(matches) != 2:
    raise SystemExit("Chef completion counts are missing")
print(sum(map(int, matches)))
PY
  )"
fi
rm -f "$attributes_file" "$chef_log"
finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ "$chef_status" -eq 0 && "$operation" == verify-idempotency &&
      "$updated_resources" -ne 0 ]]; then
  chef_status=1
  failure_stage=idempotency_updates
fi

if [[ "$chef_status" -eq 0 ]]; then
  hpc_user_fingerprint="$(
    ssh-keygen -E sha256 -lf /shared/home/hpcuser01/.ssh/id_ed25519.pub |
      awk '{print $2}'
  )"
  final_state=converged
  if [[ "$operation" == verify-idempotency ]]; then
    final_state=idempotency_verified
  fi
  evidence_state="$final_state"
  [[ "$operation" != update ]] || evidence_state=update_succeeded
  python3 "$release_root/chef/bin/convergence_state.py" --state-dir "$state_root" transition \
    --role scheduler --source-revision "$source_revision" \
    --manifest-digest "$manifest_digest" --specification-digest "$specification_digest" \
    --state "$final_state" --attempt "$attempt" --detail-code complete
  evidence_args=(--cleanup-verified)
  result=succeeded
else
  final_state=failed_retryable
  evidence_state="$final_state"
  if [[ "$operation" == update ]]; then
    final_state=failed
    evidence_state=update_failed
  elif [[ "$operation" == verify-idempotency ]]; then
    final_state=failed
    evidence_state=idempotency_failed
  elif [[ "$attempt" -ne 1 ]]; then
    final_state=replacement_required
    evidence_state=replacement_required
  fi
  python3 "$release_root/chef/bin/convergence_state.py" --state-dir "$state_root" transition \
    --role scheduler --source-revision "$source_revision" \
    --manifest-digest "$manifest_digest" --specification-digest "$specification_digest" \
    --state "$final_state" --attempt "$attempt" --detail-code "$failure_stage"
  evidence_args=(--cleanup-verified --failure-stage "$failure_stage")
  result=failed
  updated_resources=
fi

trap - ERR
record=(python3 "$release_root/chef/bin/convergence_state.py" --state-dir "$state_root" record-evidence
  --role scheduler --source-revision "$source_revision"
  --manifest-digest "$manifest_digest" --specification-digest "$specification_digest"
  --policy-revision "$policy_revision" --policy-lock-sha256 "$policy_lock_sha256"
  --attempt "$attempt" --result "$result" --state "$evidence_state"
  --started-at "$started_at" --finished-at "$finished_at"
  --dependency-receipt "$cyclecloud_receipt"
  --dependency-receipt "$environment_receipt"
  --dependency-receipt "$secret_access_receipt"
  "${evidence_args[@]}")
[[ -n "$updated_resources" ]] && record+=(--updated-resources "$updated_resources")
if [[ "$result" == succeeded ]]; then
  record+=(
    --hpc-user-uid 11200
    --hpc-user-gid 11200
    --hpc-user-key-fingerprint "$hpc_user_fingerprint"
  )
fi
"${record[@]}"

if [[ "$result" == failed ]]; then
  restore_previous_release
fi
[[ "$chef_status" -eq 0 ]] || exit "$chef_status"
