#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  echo "usage: $0 --source-revision <40-hex> --output-dir <absolute-path>" >&2
}

source_revision=
output_dir=
while (($#)); do
  case "$1" in
    --source-revision)
      source_revision="${2:-}"
      shift 2
      ;;
    --output-dir)
      output_dir="${2:-}"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || {
  echo "source revision must be a full lowercase Git commit" >&2
  exit 2
}
[[ "$output_dir" = /* ]] || {
  echo "output directory must be absolute" >&2
  exit 2
}

install -d -m 0700 "$output_dir"

python3 - "$source_revision" "$output_dir" <<'PY'
from __future__ import annotations

import gzip
import hashlib
import io
import json
import base64
from pathlib import Path
import sys
import tarfile


ROOT = Path.cwd()
SOURCE_REVISION = sys.argv[1]
OUTPUT = Path(sys.argv[2])
CHEF_VERSION = "18.11.11"
CHEF_SHA256 = "d68c339bc85ded67b793de4e20f35886c5fbd9b5a9e95dabbe5ede6211b01365"
CHEF_URI = (
    "https://chefdownload-commercial.chef.io/stable/chef/download"
)
ROLES = {
    "cyclecloud": {
        "policy": "cyclecloud",
        "cookbook": "cyclecloud_node",
        "project_name": "azure-slurm-pkg-4.0.11.tar.gz",
        "project_sha256": "f85a1d016eca3786eb9845fcbffcefaf674bfcd4b59738597e90877047a23e36",
    },
    "scheduler": {
        "policy": "slurm",
        "cookbook": "slurm_scheduler",
        "project_name": "azure-slurm-install-pkg-4.0.11.tar.gz",
        "project_sha256": "a489f4c5ec2404dc02a09792af5f32f4683e164327d89c4c2dfc8d9a30402482",
    },
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(document: object) -> bytes:
    return json.dumps(document, sort_keys=True, separators=(",", ":")).encode()


def source_revision(role: str, cookbook: str) -> str:
    digest = hashlib.sha256()
    paths = [
        ROOT / "chef" / "policyfiles" / f"{role}.rb",
        *(ROOT / "chef" / "cookbooks" / cookbook).rglob("*"),
    ]
    for path in sorted(path for path in paths if path.is_file()):
        relative = path.relative_to(ROOT / "chef").as_posix().encode()
        digest.update(relative + b"\0" + path.read_bytes() + b"\0")
    return digest.hexdigest()


def archive(role: str, policy: str, cookbook: str) -> bytes:
    roots = [
        ROOT / "chef" / "bootstrap" / "linux.sh",
        ROOT / "chef" / "bin",
        ROOT / "chef" / "cookbooks" / cookbook,
        ROOT / "chef" / "policyfiles" / f"{policy}.rb",
        ROOT / "chef" / "policyfiles" / f"{policy}.lock.json",
    ]
    if role == "cyclecloud":
        roots.append(ROOT / "tools" / "headless_template" / "src")
    files: list[Path] = []
    for root in roots:
        files.extend(path for path in root.rglob("*") if path.is_file()) if root.is_dir() else files.append(root)

    raw = io.BytesIO()
    with tarfile.open(fileobj=raw, mode="w") as tar:
        for path in sorted(files):
            relative = path.relative_to(ROOT)
            info = tar.gettarinfo(str(path), arcname=relative.as_posix())
            info.uid = 0
            info.gid = 0
            info.uname = "root"
            info.gname = "root"
            info.mtime = 0
            info.mode = 0o755 if path.suffix in {"", ".sh", ".py"} else 0o644
            with path.open("rb") as source:
                tar.addfile(info, source)
    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode="wb", mtime=0) as target:
        target.write(raw.getvalue())
    return compressed.getvalue()


for role, config in ROLES.items():
    policy = config["policy"]
    lock_path = ROOT / "chef" / "policyfiles" / f"{policy}.lock.json"
    lock = json.loads(lock_path.read_text())
    expected_revision = source_revision(policy, config["cookbook"])
    if lock.get("revision_id") != expected_revision:
        raise SystemExit(
            f"{role} Policyfile lock is stale: expected revision_id {expected_revision}"
        )

    payload = archive(role, policy, config["cookbook"])
    if len(payload) * 4 / 3 > 60_000:
        raise SystemExit(f"{role} decoded custom-data payload exceeds the 60000-byte gate")
    archive_path = OUTPUT / f"{role}.tgz"
    archive_path.write_bytes(payload)

    project_uri = (
        "https://github.com/Azure/cyclecloud-slurm/releases/download/4.0.11/"
        + config["project_name"]
    )
    manifest = {
        "schemaVersion": 1,
        "role": role,
        "sourceRevision": SOURCE_REVISION,
        "policyName": policy,
        "policyRevision": lock["revision_id"],
        "policyLockSha256": sha256(lock_path.read_bytes()),
        "policyArchiveBase64Sha256": sha256(base64.b64encode(payload)),
        "artifacts": [
            {
                "name": f"{role}.tgz",
                "kind": "policy",
                "version": SOURCE_REVISION,
                "uri": None,
                "sha256": sha256(payload),
                "sizeBytes": len(payload),
            },
            {
                "name": lock_path.name,
                "kind": "policy-lock",
                "version": lock["revision_id"],
                "uri": None,
                "sha256": sha256(lock_path.read_bytes()),
                "sizeBytes": lock_path.stat().st_size,
            },
            {
                "name": "chef-18.11.11-1.el9.x86_64.rpm",
                "kind": "package",
                "version": CHEF_VERSION,
                "uri": CHEF_URI,
                "sha256": CHEF_SHA256,
                "sizeBytes": 1,
            },
            {
                "name": config["project_name"],
                "kind": "project",
                "version": "4.0.11",
                "uri": project_uri,
                "sha256": config["project_sha256"],
                "sizeBytes": 1,
            },
        ],
    }
    manifest["manifestDigest"] = sha256(canonical(manifest))
    (OUTPUT / f"{role}.manifest.json").write_bytes(
        json.dumps(manifest, indent=2, sort_keys=True).encode() + b"\n"
    )
PY
