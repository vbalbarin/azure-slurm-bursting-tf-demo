#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "post-create.sh must run as the non-root remote user" >&2
  exit 1
fi

: "${EVIDENCE_ROOT:?EVIDENCE_ROOT is required}"
: "${EVIDENCE_DIR:?EVIDENCE_DIR is required}"
[[ "$EVIDENCE_DIR" == "$EVIDENCE_ROOT/"* ]] || {
  echo "EVIDENCE_DIR must be below EVIDENCE_ROOT" >&2
  exit 1
}
if ! mountpoint -q -- "$EVIDENCE_ROOT"; then
  printf '%s\n' \
    "Protected evidence volume is not mounted at $EVIDENCE_ROOT." \
    "Rebuild the development container so the named Docker volume is attached." \
    "Do not create a host \$HOME/evidence directory; see README.md#protected-evidence-volume." >&2
  exit 1
fi
if [[ ! -w "$EVIDENCE_ROOT" ]]; then
  if ! sudo -n chown -R "$(id -u):$(id -g)" "$EVIDENCE_ROOT"; then
    printf '%s\n' \
      "Protected evidence volume at $EVIDENCE_ROOT is not writable by $(id -un) (UID $(id -u), GID $(id -g))." \
      "Automatic ownership repair failed. See README.md#protected-evidence-volume." >&2
    exit 1
  fi
fi
chmod 0700 "$EVIDENCE_ROOT"
install -d -m 0700 "$EVIDENCE_DIR"

export PATH="$HOME/.local/bin:$PATH"
# Spec Kit v1.1.2
uv tool install --force specify-cli \
  --from "git+https://github.com/github/spec-kit.git@959e866caa3618bf3dc290d5dca33394365af9c6"
specify --version

python3 -m venv .venv
.venv/bin/python -m pip install --upgrade "pip==25.2"
.venv/bin/python -m pip install \
  --editable './tools/headless_template[dev]' \
  "checkov==3.3.26"

BUNDLE_GEMFILE=chef/Gemfile bundle config set --local path "$PWD/.bundle"
BUNDLE_GEMFILE=chef/Gemfile bundle config set --local clean true
BUNDLE_GEMFILE=chef/Gemfile bundle install --jobs 4 --retry 3
BUNDLE_GEMFILE=chef/Gemfile bundle binstubs cookstyle --path "$HOME/.local/bin" --force

terraform -chdir=terraform init -backend=false
printf '%s\n' \
  "Development runtimes installed without host-level privilege." \
  "Run 'make validate' to execute local source gates." \
  "Protected evidence is stored outside Git in $EVIDENCE_DIR." \
  "Azure deployment still requires an authorized 'az login' and protected inputs."
