#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "post-create.sh must run as the non-root remote user" >&2
  exit 1
fi

python3 -m venv .venv
.venv/bin/python -m pip install --upgrade "pip==25.2"
.venv/bin/python -m pip install \
  --editable './tools/headless_template[dev]' \
  "checkov==3.3.26"

BUNDLE_GEMFILE=chef/Gemfile bundle config set --local path "$PWD/.bundle"
BUNDLE_GEMFILE=chef/Gemfile bundle config set --local clean true
BUNDLE_GEMFILE=chef/Gemfile bundle install --jobs 4 --retry 3

terraform -chdir=terraform init -backend=false
printf '%s\n' \
  "Development runtimes installed without host-level privilege." \
  "Run 'make validate' to execute local source gates." \
  "Azure deployment still requires an authorized 'az login' and protected inputs."
