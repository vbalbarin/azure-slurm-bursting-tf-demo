#!/usr/bin/env bash
set -euo pipefail
umask 077

readonly release_root="${SLURM_DEMO_CURRENT:-/opt/slurm-demo/current}"
readonly state_root="${SLURM_DEMO_STATE_ROOT:-/var/lib/slurm-demo}"
readonly role_state="$state_root/cyclecloud"
readonly manifest="$release_root/manifest.json"
readonly specification="$release_root/node-specification.json"
readonly policy_lock="$release_root/chef/policyfiles/cyclecloud.lock.json"
readonly state_tool="$release_root/chef/bin/convergence_state.py"
readonly runtime_dir="${SLURM_DEMO_RUNTIME_ROOT:-/run/slurm-demo}/cyclecloud"
readonly operation="${CONVERGENCE_OPERATION:-initial}"
readonly previous_release="${SLURM_DEMO_PREVIOUS_RELEASE:-}"
readonly previous_state="${SLURM_DEMO_PREVIOUS_STATE:-}"

case "$operation" in
  initial|retry|update|verify-idempotency) ;;
  *) echo "Unsupported CycleCloud convergence operation" >&2; exit 2 ;;
esac
if [[ "$operation" == update ]]; then
  [[ -d "$previous_release" && -f "$previous_state" ]] || {
    echo "CycleCloud update requires the prior release and state snapshot" >&2
    exit 2
  }
fi

install -d -m 0700 "$role_state" "$runtime_dir"
exec 9>"$role_state/wrapper.lock"
flock -n 9 || {
  echo "CycleCloud convergence is already active" >&2
  exit 75
}

# shellcheck disable=SC2317
cleanup() {
  rm -rf "$runtime_dir"
}
trap cleanup EXIT

restore_previous_release() {
  [[ "$operation" == update ]] || return 0
  python3 - "$previous_release" "$previous_state" "$release_root" "$state_file" <<'PY'
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
  python3 - "$manifest" "$specification" "$policy_lock" <<'PY'
import hashlib
import json
from pathlib import Path
import re
import sys

manifest_path, specification_path, lock_path = map(Path, sys.argv[1:])
manifest = json.loads(manifest_path.read_text())
specification = json.loads(specification_path.read_text())
policy_lock = json.loads(lock_path.read_text())

def canonical_digest(document, digest_field):
    value = dict(document)
    value.pop(digest_field, None)
    return hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()

checks = (
    (manifest.get("role") == "cyclecloud", "manifest role mismatch"),
    (manifest.get("policyName") == "cyclecloud", "policy name mismatch"),
    (specification.get("role") == "cyclecloud", "specification role mismatch"),
    (
        manifest.get("sourceRevision") == specification.get("sourceRevision"),
        "source revision mismatch",
    ),
    (
        manifest.get("manifestDigest") == canonical_digest(manifest, "manifestDigest"),
        "manifest digest mismatch",
    ),
    (
        specification.get("specificationDigest")
        == canonical_digest(specification, "specificationDigest"),
        "specification digest mismatch",
    ),
    (
        manifest.get("policyRevision") == policy_lock.get("revision_id"),
        "policy revision mismatch",
    ),
    (
        policy_lock.get("run_list") == ["recipe[cyclecloud_node::default]"],
        "policy run list mismatch",
    ),
    (
        manifest.get("policyLockSha256")
        == hashlib.sha256(lock_path.read_bytes()).hexdigest(),
        "policy lock digest mismatch",
    ),
)
for accepted, message in checks:
    if not accepted:
        raise SystemExit(message)
for value in (
    manifest.get("policyRevision", ""),
    manifest.get("policyLockSha256", ""),
    manifest.get("manifestDigest", ""),
    specification.get("specificationDigest", ""),
):
    if not re.fullmatch(r"[0-9a-f]{64}", value):
        raise SystemExit("invalid verified digest")
project = [
    artifact
    for artifact in manifest.get("artifacts", [])
    if artifact.get("kind") == "project"
]
if len(project) != 1 or project[0] != {
    "name": "azure-slurm-pkg-4.0.11.tar.gz",
    "kind": "project",
    "version": "4.0.11",
    "uri": "https://github.com/Azure/cyclecloud-slurm/releases/download/4.0.11/azure-slurm-pkg-4.0.11.tar.gz",
    "sha256": "f85a1d016eca3786eb9845fcbffcefaf674bfcd4b59738597e90877047a23e36",
    "sizeBytes": project[0].get("sizeBytes"),
}:
    raise SystemExit("CycleCloud Slurm project identity mismatch")
print(
    manifest["sourceRevision"],
    manifest["manifestDigest"],
    specification["specificationDigest"],
    manifest["policyRevision"],
    manifest["policyLockSha256"],
    policy_lock["run_list"][0],
)
PY
)"
read -r source_revision manifest_digest specification_digest policy_revision \
  policy_lock_sha256 chef_run_list <<<"$validation"

state_file="$role_state/state.json"
attempt=1
if [[ -f "$state_file" ]]; then
  current_state="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$state_file")"
  case "$current_state" in
    converged|idempotency_verified)
      if [[ "$operation" == initial ]]; then
        exit 0
      fi
      ;;
    failed_retryable)
      attempt=2
      ;;
    replacement_required)
      echo "CycleCloud VM replacement is required" >&2
      exit 78
      ;;
  esac
fi
transition_state=converging
if [[ "$operation" == verify-idempotency ]]; then
  transition_state=verifying_idempotency
  attempt="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["attempt"])' "$state_file")"
fi

state_common=(
  --role cyclecloud
  --source-revision "$source_revision"
  --manifest-digest "$manifest_digest"
  --specification-digest "$specification_digest"
)
python3 "$state_tool" --state-dir "$state_root" transition \
  "${state_common[@]}" --state "$transition_state" --attempt "$attempt" --detail-code chef_started

started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
readonly started_at
readonly chef_log="$runtime_dir/chef.log"
readonly chef_config="$runtime_dir/client.rb"
install -d -m 0700 "$runtime_dir/cache"
printf '%s\n' \
  "chef_repo_path \"$release_root\"" \
  "cookbook_path [\"$release_root/chef/cookbooks\"]" \
  "file_cache_path \"$runtime_dir/cache\"" >"$chef_config"
chmod 0600 "$chef_config"
if CHEF_LICENSE=accept-no-persist chef-client --local-mode \
  --config "$chef_config" \
  --override-runlist "$chef_run_list" \
  --json-attributes "$specification" \
  --log_level warn >"$chef_log" 2>&1; then
  finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated_resources="$(
    python3 - "$chef_log" <<'PY'
from pathlib import Path
import re
import sys

matches = re.findall(r"Chef Infra Client finished, (\d+)/\d+ resources updated", Path(sys.argv[1]).read_text())
if len(matches) != 1:
    raise SystemExit("Chef completion count is missing")
print(matches[0])
PY
  )"
  rm -rf "$runtime_dir"
  if [[ "$operation" == verify-idempotency && "$updated_resources" -ne 0 ]]; then
    python3 "$state_tool" --state-dir "$state_root" transition \
      "${state_common[@]}" --state failed --attempt "$attempt" \
      --detail-code idempotency_updates
    python3 "$state_tool" --state-dir "$state_root" record-evidence \
      "${state_common[@]}" \
      --policy-revision "$policy_revision" \
      --policy-lock-sha256 "$policy_lock_sha256" \
      --attempt "$attempt" \
      --result failed \
      --state idempotency_failed \
      --updated-resources "$updated_resources" \
      --started-at "$started_at" \
      --finished-at "$finished_at" \
      --failure-stage idempotency_updates \
      --cleanup-verified
    trap - EXIT
    echo "CycleCloud idempotency verification updated resources" >&2
    exit 1
  fi
  final_state=converged
  evidence_state=converged
  if [[ "$operation" == verify-idempotency ]]; then
    final_state=idempotency_verified
    evidence_state=idempotency_verified
  elif [[ "$operation" == update ]]; then
    evidence_state=update_succeeded
  fi
  python3 "$state_tool" --state-dir "$state_root" transition \
    "${state_common[@]}" --state "$final_state" --attempt "$attempt" --detail-code chef_succeeded
  python3 "$state_tool" --state-dir "$state_root" record-evidence \
    "${state_common[@]}" \
    --policy-revision "$policy_revision" \
    --policy-lock-sha256 "$policy_lock_sha256" \
    --attempt "$attempt" \
    --result succeeded \
    --state "$evidence_state" \
    --updated-resources "$updated_resources" \
    --started-at "$started_at" \
    --finished-at "$finished_at" \
    --cleanup-verified
  trap - EXIT
  exit 0
fi

finished_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
rm -rf "$runtime_dir"
failure_state=failed_retryable
evidence_state=failed_retryable
if [[ "$operation" == verify-idempotency ]]; then
  failure_state=failed
  evidence_state=idempotency_failed
elif [[ "$operation" == update ]]; then
  failure_state=failed
  evidence_state=update_failed
elif [[ "$attempt" -eq 2 ]]; then
  failure_state=replacement_required
  evidence_state=replacement_required
fi
python3 "$state_tool" --state-dir "$state_root" transition \
  "${state_common[@]}" --state "$failure_state" --attempt "$attempt" --detail-code chef_failed
python3 "$state_tool" --state-dir "$state_root" record-evidence \
  "${state_common[@]}" \
  --policy-revision "$policy_revision" \
  --policy-lock-sha256 "$policy_lock_sha256" \
  --attempt "$attempt" \
  --result failed \
  --state "$evidence_state" \
  --started-at "$started_at" \
  --finished-at "$finished_at" \
  --failure-stage chef \
  --cleanup-verified
restore_previous_release
trap - EXIT
echo "CycleCloud convergence failed" >&2
exit 1
