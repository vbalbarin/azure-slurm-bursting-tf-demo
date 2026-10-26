#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  echo "usage: $0 --source-revision <40-hex> --specification-digest <64-hex> --output <absolute-path>" >&2
}

source_revision=
specification_digest=
output=
while (($#)); do
  case "$1" in
    --source-revision) source_revision="${2:-}"; shift 2 ;;
    --specification-digest) specification_digest="${2:-}"; shift 2 ;;
    --output) output="${2:-}"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done

[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || { echo "invalid source revision" >&2; exit 2; }
[[ "$specification_digest" =~ ^[0-9a-f]{64}$ ]] || { echo "invalid specification digest" >&2; exit 2; }
[[ "$output" = /* ]] || { echo "receipt output must be absolute" >&2; exit 2; }

IFS=: read -r name _ uid gid _ home _ < <(getent passwd hpcuser01)
[[ "$name" == hpcuser01 && "$uid" == 11200 && "$gid" == 11200 ]] || {
  echo "unexpected hpcuser01 identity" >&2
  exit 1
}
[[ "$home" == /shared/home/hpcuser01 ]] || {
  echo "unexpected hpcuser01 home" >&2
  exit 1
}

public_key_path="${HPC_PUBLIC_KEY_PATH:-$home/.ssh/id_ed25519.pub}"
[[ -f "$public_key_path" && ! -L "$public_key_path" ]] || {
  echo "hpcuser01 public key is missing or unsafe" >&2
  exit 1
}
read -r key_type key_body _ extra <"$public_key_path"
[[ "$key_type" == ssh-ed25519 && -n "$key_body" && -z "${extra:-}" ]] || {
  echo "hpcuser01 must have exactly one Ed25519 public key" >&2
  exit 1
}
[[ "$(wc -l <"$public_key_path")" -eq 1 ]] || {
  echo "hpcuser01 public key file must contain one key" >&2
  exit 1
}
public_key="$key_type $key_body"
fingerprint="$(ssh-keygen -E sha256 -lf "$public_key_path" | awk '{print $2}')"
[[ "$fingerprint" =~ ^SHA256:[A-Za-z0-9+/]{16,}={0,2}$ ]] || {
  echo "invalid hpcuser01 public key fingerprint" >&2
  exit 1
}

install -d -m 0700 "$(dirname "$output")"
python3 - "$output" "$source_revision" "$specification_digest" "$public_key" "$fingerprint" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import sys

output, source_revision, specification_digest, public_key, fingerprint = sys.argv[1:]
receipt = {
    "schemaVersion": 1,
    "name": "hpcuser01",
    "uid": 11200,
    "gid": 11200,
    "home": "/shared/home/hpcuser01",
    "publicKey": public_key,
    "publicKeyFingerprint": fingerprint,
    "sourceRevision": source_revision,
    "specificationDigest": specification_digest,
}
canonical = json.dumps(receipt, sort_keys=True, separators=(",", ":")).encode()
receipt["identityReceiptDigest"] = hashlib.sha256(canonical).hexdigest()
path = Path(output)
temporary = path.with_name(f".{path.name}.{os.getpid()}")
descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
        json.dump(receipt, stream, indent=2, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
finally:
    temporary.unlink(missing_ok=True)
PY
