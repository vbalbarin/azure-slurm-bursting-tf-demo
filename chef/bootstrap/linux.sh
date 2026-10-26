#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${CHEF_POLICY_NAME:?CHEF_POLICY_NAME is required}"
: "${CHEF_MANIFEST_PATH:?CHEF_MANIFEST_PATH is required}"
: "${CHEF_NODE_SPECIFICATION_PATH:?CHEF_NODE_SPECIFICATION_PATH is required}"
: "${CHEF_POLICY_ARCHIVE_PATH:?CHEF_POLICY_ARCHIVE_PATH is required}"

case "$CHEF_POLICY_NAME" in
  cyclecloud|slurm) ;;
  *) echo "Unsupported Chef policy" >&2; exit 2 ;;
esac

chef_version=18.11.11
chef_rpm_sha256=d68c339bc85ded67b793de4e20f35886c5fbd9b5a9e95dabbe5ede6211b01365
chef_rpm_uri=https://packages.chef.io/files/stable/chef/18.11.11/el/9/chef-18.11.11-1.el9.x86_64.rpm
release_root=/opt/slurm-demo/releases
state_root=/var/lib/slurm-demo
install -d -m 0700 "$release_root" "$state_root"

validation="$(
  python3 - "$CHEF_POLICY_NAME" "$CHEF_MANIFEST_PATH" \
    "$CHEF_NODE_SPECIFICATION_PATH" "$CHEF_POLICY_ARCHIVE_PATH" <<'PY'
import hashlib
import json
from pathlib import Path
import re
import sys

policy, manifest_path, specification_path, archive_path = sys.argv[1:]
manifest = json.loads(Path(manifest_path).read_text())
specification = json.loads(Path(specification_path).read_text())

def canonical_digest(document):
    value = dict(document)
    value.pop("manifestDigest", None)
    value.pop("specificationDigest", None)
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()

if manifest.get("manifestDigest") != canonical_digest(manifest):
    raise SystemExit("manifestDigest mismatch")
if specification.get("specificationDigest") != canonical_digest(specification):
    raise SystemExit("specificationDigest mismatch")
expected_role = "scheduler" if policy == "slurm" else "cyclecloud"
if manifest.get("role") != expected_role or specification.get("role") != expected_role:
    raise SystemExit("role mismatch")
if manifest.get("sourceRevision") != specification.get("sourceRevision"):
    raise SystemExit("source revision mismatch")
if not re.fullmatch(r"[0-9a-f]{64}", manifest.get("policyLockSha256", "")):
    raise SystemExit("invalid policyLockSha256")
archive = Path(archive_path).read_bytes()
artifact = next(
    (item for item in manifest.get("artifacts", []) if item.get("kind") == "policy"),
    None,
)
if artifact is None or artifact.get("sha256") != hashlib.sha256(archive).hexdigest():
    raise SystemExit("policy artifact digest mismatch")
print(
    manifest["sourceRevision"],
    manifest["manifestDigest"],
    specification["specificationDigest"],
    artifact["sha256"],
)
PY
)"
read -r source_revision manifest_digest specification_digest policy_digest <<<"$validation"

release_path="$release_root/$policy_digest"
if [[ ! -d "$release_path" ]]; then
  candidate="$(mktemp -d "$release_root/.candidate.XXXXXX")"
  cleanup_candidate() {
    rm -rf "$candidate"
  }
  trap cleanup_candidate EXIT

  tar --extract --gzip --file "$CHEF_POLICY_ARCHIVE_PATH" --directory "$candidate"
  lock_path="$candidate/chef/policyfiles/$CHEF_POLICY_NAME.lock.json"
  [[ -f "$lock_path" ]] || {
    echo "Policy lock is missing" >&2
    exit 1
  }
  [[ "$(sha256sum "$lock_path" | awk '{print $1}')" == "$(
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["policyLockSha256"])' \
      "$CHEF_MANIFEST_PATH"
  )" ]] || {
    echo "Policy lock digest mismatch" >&2
    exit 1
  }
  [[ "$(
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["revision_id"])' "$lock_path"
  )" == "$(
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["policyRevision"])' \
      "$CHEF_MANIFEST_PATH"
  )" ]] || {
    echo "Policy lock revision mismatch" >&2
    exit 1
  }

  install -m 0444 "$CHEF_MANIFEST_PATH" "$candidate/manifest.json"
  install -m 0444 "$CHEF_NODE_SPECIFICATION_PATH" "$candidate/node-specification.json"
  chmod -R go-w "$candidate"
  mv "$candidate" "$release_path"
  trap - EXIT
fi

if ! command -v chef-client >/dev/null 2>&1 ||
   [[ "$(chef-client --version 2>/dev/null | awk '{print $2}')" != "$chef_version" ]]; then
  rpm_path="$(mktemp /var/tmp/chef.XXXXXX.rpm)"
  cleanup_rpm() {
    rm -f "$rpm_path"
  }
  trap cleanup_rpm EXIT
  curl --fail --silent --show-error --proto '=https' --tlsv1.2 \
    "$chef_rpm_uri" --output "$rpm_path"
  [[ "$(sha256sum "$rpm_path" | awk '{print $1}')" == "$chef_rpm_sha256" ]] || {
    echo "Chef RPM digest mismatch" >&2
    exit 1
  }
  rpm --upgrade --replacepkgs "$rpm_path"
  rm -f "$rpm_path"
  trap - EXIT
fi

python3 - "$release_path" <<'PY'
import os
from pathlib import Path
import sys

release = Path(sys.argv[1])
current = release.parent.parent / "current"
temporary = release.parent.parent / ".current.new"
temporary.unlink(missing_ok=True)
temporary.symlink_to(release)
os.replace(temporary, current)
PY

role=cyclecloud
state=environment_ready
if [[ "$CHEF_POLICY_NAME" == slurm ]]; then
  role=scheduler
  state=waiting_dependencies
fi
python3 "$release_path/chef/bin/convergence_state.py" --state-dir "$state_root" transition \
  --role "$role" \
  --source-revision "$source_revision" \
  --manifest-digest "$manifest_digest" \
  --specification-digest "$specification_digest" \
  --state "$state" \
  --attempt 0 \
  --detail-code staged
