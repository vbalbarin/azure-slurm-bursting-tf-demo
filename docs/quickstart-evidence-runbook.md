# Evidence Runbook: Backend Bootstrap and Slurm Bursting Demo

This runbook is the detailed operator companion to:

- [`specs/003-terraform-backend-bootstrap/quickstart.md`](../specs/003-terraform-backend-bootstrap/quickstart.md)
  for the Terraform state backend; and
- [`specs/002-slurm-bursting-demo/quickstart.md`](../specs/002-slurm-bursting-demo/quickstart.md)
  for the Slurm bursting demonstration.

Use it only for a new approved acceptance run. The stopped backend run
`20261013T164853Z` is immutable and must never be resumed, amended, or reused.

The commands below are operator actions, not an unattended deployment script. An accountable
operator must review each result and stop on failure. Do not replace the direct Terraform or Azure
commands with a custom Bash or Python provisioning, readiness, migration, lifecycle, apply,
unlock, or destroy wrapper.

Keep `errexit` disabled in the interactive operator shell. The runbook captures expected nonzero
statuses explicitly, and a failed assertion must leave the shell alive so protected environment
variables remain available for diagnosis or cleanup. Repository scripts use `set -e` only inside
their child processes; their exit statuses are captured by the calling snippets. Do not continue
to the next code block after a nonzero status or failed `test`.

## 1. Evidence and protected-state boundaries

The development container provides two separate named volumes:

| Location | Purpose | May contain |
|---|---|---|
| `/state` | Protected operational state | Terraform state, state backups, saved plans, `.tfvars`, readiness/lifecycle assertion inputs, approval records |
| `/evidence` | Secret-free acceptance evidence | Bounded results, digests, schema-valid outputs, approval references, timings, validation summaries |
| Git workspace | Source only | Tracked examples and documentation; never live inputs, plans, state, credentials, or evidence |

Never copy Terraform state, state backups, saved plans, `.tfvars`, readiness assertion inputs,
lifecycle assertion inputs, Azure access tokens, credentials, certificate material, raw
environment dumps, or unreviewed raw command output into `/evidence`.

Do not enable `set -x`, print protected environment variables, run `az account
get-access-token`, or tee commands that can emit credentials. `/evidence` is not automatically
backed up. Export completed evidence through an approved protected channel before deleting the
container or its named volume.

### 1.1 Start a new run

Open a terminal in the development container:

```bash
cd /workspaces/azure-slurm-bursting-tf-demo
umask 077
set +e

export RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
test "$RUN_ID" != "20261013T164853Z"

export RUN_EVIDENCE_DIR="/evidence/quickstart/$RUN_ID"
export BACKEND_EVIDENCE_DIR="$RUN_EVIDENCE_DIR/backend-bootstrap"
export DEMO_EVIDENCE_DIR="$RUN_EVIDENCE_DIR/slurm-demo"
export DEMO_STATE_DIR="/state/slurm-demo/$RUN_ID"

install -d -m 0700 \
  "$BACKEND_EVIDENCE_DIR" \
  "$DEMO_EVIDENCE_DIR" \
  "$DEMO_STATE_DIR"

test -w "$BACKEND_EVIDENCE_DIR"
test -w "$DEMO_EVIDENCE_DIR"
test -w "$DEMO_STATE_DIR"
```

Use this helper only for commands whose documented output is safe to retain:

```bash
run_logged() {
  local output_file="$1"
  shift

  printf '\n[%s] Running:' "$(date -u +%FT%TZ)"
  printf ' %q' "$@"
  printf '\n'

  "$@" 2>&1 | tee "$output_file"
  local command_status="${PIPESTATUS[0]}"

  printf '[%s] Exit status: %d\n' \
    "$(date -u +%FT%TZ)" \
    "$command_status" |
    tee -a "$output_file"

  return "$command_status"
}

tee_output() {
  local output_file="$1"
  shift

  "$@" | tee "$output_file"
  local command_status="${PIPESTATUS[0]}"
  return "$command_status"
}
```

Define an environment-only persistence helper. It writes no credentials, assertions, status flags,
digests, approval references, or command results and performs no Azure or Terraform operation:

```bash
persist_run_context() {
  : "${RUN_ID:?RUN_ID is required}"
  : "${SOURCE_COMMIT:?SOURCE_COMMIT is required}"
  : "${RUN_EVIDENCE_DIR:?RUN_EVIDENCE_DIR is required}"
  : "${BACKEND_EVIDENCE_DIR:?BACKEND_EVIDENCE_DIR is required}"
  : "${DEMO_EVIDENCE_DIR:?DEMO_EVIDENCE_DIR is required}"
  : "${DEMO_STATE_DIR:?DEMO_STATE_DIR is required}"

  export RUN_CONTEXT_DIR="/state/evidence-runs/$RUN_ID"
  export RUN_CONTEXT_FILE="$RUN_CONTEXT_DIR/run-context.env"
  local temporary_file="$RUN_CONTEXT_FILE.tmp"

  install -d -m 0700 "$RUN_CONTEXT_DIR"
  {
    printf '# Generated run context. Contains paths and immutable identifiers only.\n'
    printf 'export RUN_ID=%q\n' "$RUN_ID"
    printf 'export SOURCE_COMMIT=%q\n' "$SOURCE_COMMIT"
    printf 'export RUN_EVIDENCE_DIR=%q\n' "$RUN_EVIDENCE_DIR"
    printf 'export BACKEND_EVIDENCE_DIR=%q\n' "$BACKEND_EVIDENCE_DIR"
    printf 'export DEMO_EVIDENCE_DIR=%q\n' "$DEMO_EVIDENCE_DIR"
    printf 'export DEMO_STATE_DIR=%q\n' "$DEMO_STATE_DIR"
    printf 'export RUN_CONTEXT_DIR=%q\n' "$RUN_CONTEXT_DIR"
    printf 'export RUN_CONTEXT_FILE=%q\n' "$RUN_CONTEXT_FILE"

    if test -n "${BACKEND_ENVIRONMENT:-}"; then
      printf 'export BACKEND_ENVIRONMENT=%q\n' "$BACKEND_ENVIRONMENT"
    fi
    if test -n "${BOOTSTRAP_STATE_ROOT:-}"; then
      printf 'export BOOTSTRAP_STATE_ROOT=%q\n' "$BOOTSTRAP_STATE_ROOT"
    fi
    if test -n "${BOOTSTRAP_STATE_DIR:-}"; then
      printf 'export BOOTSTRAP_STATE_DIR=%q\n' "$BOOTSTRAP_STATE_DIR"
    fi
    if test -n "${BOOTSTRAP_TFVARS:-}"; then
      printf 'export BOOTSTRAP_TFVARS=%q\n' "$BOOTSTRAP_TFVARS"
    fi
    if test -n "${BOOTSTRAP_LOCAL_STATE:-}"; then
      printf 'export BOOTSTRAP_LOCAL_STATE=%q\n' "$BOOTSTRAP_LOCAL_STATE"
    fi
    if test -n "${BACKEND_COORDINATES_FILE:-}"; then
      printf 'export BACKEND_COORDINATES_FILE=%q\n' "$BACKEND_COORDINATES_FILE"
    fi
    if test -n "${TFVARS_FILE:-}"; then
      printf 'export TFVARS_FILE=%q\n' "$TFVARS_FILE"
    fi
    if test -n "${PREFLIGHT_RESULTS_FILE:-}"; then
      printf 'export PREFLIGHT_RESULTS_FILE=%q\n' "$PREFLIGHT_RESULTS_FILE"
    fi
    if test -n "${PROBE_TFVARS_FILE:-}"; then
      printf 'export PROBE_TFVARS_FILE=%q\n' "$PROBE_TFVARS_FILE"
    fi
    if test -n "${PROBE_PLAN_FILE:-}"; then
      printf 'export PROBE_PLAN_FILE=%q\n' "$PROBE_PLAN_FILE"
    fi
    if test -n "${PROBE_APPROVAL_FILE:-}"; then
      printf 'export PROBE_APPROVAL_FILE=%q\n' "$PROBE_APPROVAL_FILE"
    fi
    if test -n "${PROBE_DESTROY_PLAN_FILE:-}"; then
      printf 'export PROBE_DESTROY_PLAN_FILE=%q\n' "$PROBE_DESTROY_PLAN_FILE"
    fi
    if test -n "${PROBE_CLEANUP_APPROVAL_FILE:-}"; then
      printf 'export PROBE_CLEANUP_APPROVAL_FILE=%q\n' \
        "$PROBE_CLEANUP_APPROVAL_FILE"
    fi
    if test -n "${PROBE_EVIDENCE_DIR:-}"; then
      printf 'export PROBE_EVIDENCE_DIR=%q\n' "$PROBE_EVIDENCE_DIR"
    fi
    if test -n "${PLAN_FILE:-}"; then
      printf 'export PLAN_FILE=%q\n' "$PLAN_FILE"
    fi
    if test -n "${APPROVAL_FILE:-}"; then
      printf 'export APPROVAL_FILE=%q\n' "$APPROVAL_FILE"
    fi
    if test -n "${CAPACITY_PROBE_RESULTS_FILE:-}"; then
      printf 'export CAPACITY_PROBE_RESULTS_FILE=%q\n' \
        "$CAPACITY_PROBE_RESULTS_FILE"
    fi
    if test -n "${FOUNDATION_PLAN_FILE:-}"; then
      printf 'export FOUNDATION_PLAN_FILE=%q\n' "$FOUNDATION_PLAN_FILE"
    fi
    if test -n "${KEY_VAULT_RECONCILIATION_PLAN_FILE:-}"; then
      printf 'export KEY_VAULT_RECONCILIATION_PLAN_FILE=%q\n' \
        "$KEY_VAULT_RECONCILIATION_PLAN_FILE"
    fi
    if test -n "${KEY_VAULT_RECONCILIATION_APPROVAL_FILE:-}"; then
      printf 'export KEY_VAULT_RECONCILIATION_APPROVAL_FILE=%q\n' \
        "$KEY_VAULT_RECONCILIATION_APPROVAL_FILE"
    fi
    if test -n "${KEY_VAULT_PROVISIONING_EVIDENCE_FILE:-}"; then
      printf 'export KEY_VAULT_PROVISIONING_EVIDENCE_FILE=%q\n' \
        "$KEY_VAULT_PROVISIONING_EVIDENCE_FILE"
    fi
    declare -f persist_run_context
  } >"$temporary_file"

  bash -n "$temporary_file"
  chmod 0600 "$temporary_file"
  mv "$temporary_file" "$RUN_CONTEXT_FILE"

  test ! -L "$RUN_CONTEXT_FILE"
  test "$(stat -c '%a' "$RUN_CONTEXT_FILE")" = "600"
  test "$(stat -c '%u' "$RUN_CONTEXT_FILE")" = "$(id -u)"
}
```

Use `tee_output` only when a command's stdout is explicitly secret-free and must remain valid JSON,
Markdown, or digest output. Record non-secret run metadata:

```bash
export SOURCE_COMMIT="$(git rev-parse HEAD)"

tee_output "$RUN_EVIDENCE_DIR/run-metadata.json" \
  jq -n \
  --arg run_id "$RUN_ID" \
  --arg started_at "$(date -u +%FT%TZ)" \
  --arg commit "$SOURCE_COMMIT" \
  --arg branch "$(git branch --show-current)" \
  '{
    run_id: $run_id,
    started_at: $started_at,
    source_commit: $commit,
    branch: $branch
  }'

tee_output "$RUN_EVIDENCE_DIR/git-status.txt" \
  git --no-pager status --short
test ! -s "$RUN_EVIDENCE_DIR/git-status.txt"
printf 'Git worktree is clean at %s.\n' "$SOURCE_COMMIT"

persist_run_context
```

Stop if the worktree is not clean. The evidence must identify the exact tested commit.

### 1.2 Resume an interrupted operator shell

Use only the protected file created by this run. Never source a context file received from another
operator, run, repository, or untrusted path:

```bash
cd /workspaces/azure-slurm-bursting-tf-demo
umask 077
set +e

export RUN_ID="<existing-run-id>"
export RUN_CONTEXT_FILE="/state/evidence-runs/$RUN_ID/run-context.env"

test -f "$RUN_CONTEXT_FILE"
test ! -L "$RUN_CONTEXT_FILE"
test "$(stat -c '%a' "$RUN_CONTEXT_FILE")" = "600"
test "$(stat -c '%u' "$RUN_CONTEXT_FILE")" = "$(id -u)"
bash -n "$RUN_CONTEXT_FILE"
```

If any validation fails, do not source the file. Otherwise source it and bind the reconstructed
shell to immutable run metadata and source:

```bash
source "$RUN_CONTEXT_FILE"
set +e

test "$SOURCE_COMMIT" = "$(git rev-parse HEAD)"
test "$RUN_ID" = "$(jq -r '.run_id' "$RUN_EVIDENCE_DIR/run-metadata.json")"
test "$SOURCE_COMMIT" = "$(
  jq -r '.source_commit' "$RUN_EVIDENCE_DIR/run-metadata.json"
)"
test -z "$(git status --short)"
```

Reauthenticate to Azure and repeat the section's current identity, network, DNS, digest, timing,
and command-result observations. The context file is a path cache only. It is never authority for
current authentication, readiness, approval, plan, migration, lifecycle, cleanup, or acceptance
status.

### 1.3 Authenticate to the approved Azure context

```bash
az login
az account set --subscription "<approved-subscription-id>"

tee_output "$RUN_EVIDENCE_DIR/azure-account.json" \
  az account show \
    --query '{subscription_id:id,subscription_name:name,tenant_id:tenantId,user_type:user.type}' \
    --output json
```

Confirm the returned subscription and tenant before proceeding. Record RBAC propagation delay
separately from execution time; waiting for role propagation is never evidence that an operation
succeeded.

## 2. Validate the exact source

Run the repository validation entry points before either live workflow:

```bash
run_logged "$RUN_EVIDENCE_DIR/01-make-validate.log" make validate
run_logged "$RUN_EVIDENCE_DIR/02-chef-style.log" make chef-style
run_logged "$RUN_EVIDENCE_DIR/03-chef-unit.log" make chef-unit
```

`make validate` covers all three Terraform roots, native Terraform tests, TFLint, Checkov,
AVM-only policy tests, backend contracts and evidence schemas, end-to-end unit tests, Python
typing, Bandit, and processor tests. Chef style and unit tests are separate targets.

`make chef-integration` creates Azure Test Kitchen resources. Run it only after Azure
authentication, Marketplace acceptance, and protected inputs are ready:

```bash
run_logged "$DEMO_EVIDENCE_DIR/04-chef-integration.log" make chef-integration
```

Stop on any nonzero status. Do not continue with stale validation from another commit.

---

# Part A: Terraform backend bootstrap

Complete Part A before initializing the main or capacity-probe roots against the remote backend.
Bootstrap acceptance must complete within 20 minutes of active execution, excluding separately
measured Entra role-propagation and authorized plan-approval wait intervals. Command failures,
investigation, retries, and ordinary execution time are never excluded.

Choose the execution order before starting:

- **Backend-only acceptance:** run A1 through A10. This validates removal and leaves no backend for
  Part B.
- **Combined backend and Slurm acceptance:** run A1 through A8, retain the backend through A11,
  run B1 through B10, perform A9 recovery while all three state namespaces still exist, run B11
  cleanup, and then return to A10. This is the path that leaves a usable backend in place while
  Part B runs.

Do not run A10 before Part B in a combined run. A10 deliberately removes the managed backend.

## A1. Select the ownership and network modes

Choose one approved ownership mode:

- `managed`: Terraform creates and owns the resource group, storage account, private `tfstate`
  container, role assignments, network controls, recovery controls, and `CanNotDelete` lock.
- `existing`: Terraform validates approved coordinates and creates, imports, mutates, locks,
  unlocks, or destroys no organizational resource.

Choose one approved network mode:

- `restricted_public`: default-deny with explicit current public IPv4 `/32` CIDRs; never use
  `0.0.0.0/0`.
- `private`: public access disabled and an existing reachable subnet plus the
  `privatelink.blob.core.windows.net` private DNS zone.

Never enable unrestricted public access as a fallback for failed DNS, routing, or authorization.

For restricted-public mode, discover the current public IPv4 address from the actual runner:

```bash
export PUBLIC_IPV4="$(
  curl --ipv4 \
    --fail \
    --silent \
    --show-error \
    https://api.ipify.org
)"

printf 'allowed_public_ipv4_cidrs = ["%s/32"]\n' "$PUBLIC_IPV4"
```

Use the printed `/32` value in `allowed_public_ipv4_cidrs`. Run the command after connecting any
required VPN or proxy and from the same runner/network context that will access the backend. A
network-context change can alter the public address and invalidates the associated readiness
assessment. The bootstrap preserves `/32` as the reviewed input but sends Azure Storage the bare
IPv4 address required for a single-address firewall rule.

`api.ipify.org` is an external service and observes the request's source address. Use it only when
approved by organizational policy. Otherwise obtain the runner's egress IPv4 address through the
approved network-administration path. Never send a token, credential, hostname, username, or query
parameter to the echo service.

## A2. Prepare protected inputs and local state

```bash
export BACKEND_ENVIRONMENT="demo"
export BOOTSTRAP_STATE_ROOT="${BOOTSTRAP_STATE_ROOT:-/state/terraform-backend}"
export BOOTSTRAP_STATE_DIR="$BOOTSTRAP_STATE_ROOT/$BACKEND_ENVIRONMENT"
export BOOTSTRAP_TFVARS="$BOOTSTRAP_STATE_DIR/bootstrap.tfvars"
export BOOTSTRAP_LOCAL_STATE="$BOOTSTRAP_STATE_DIR/terraform.tfstate"
export BOOTSTRAP_STARTED_EPOCH="$(date +%s)"

install -d -m 0700 "$BOOTSTRAP_STATE_DIR"
cp terraform/bootstrap/bootstrap.tfvars.example "$BOOTSTRAP_TFVARS"
chmod 0600 "$BOOTSTRAP_TFVARS"

persist_run_context
```

For an interactive `az login`, obtain the active user's Entra object ID and tenant:

```bash
test "$(az account show --query user.type --output tsv)" = "user"

export READINESS_TENANT_ID="$(
  az account show --query tenantId --output tsv
)"
export READINESS_PRINCIPAL_ID="$(
  az ad signed-in-user show --query id --output tsv
)"
export READINESS_PRINCIPAL_TYPE="User"

printf 'readiness_identity tenant_id: %s\n' "$READINESS_TENANT_ID"
printf 'readiness_identity principal_id: %s\n' "$READINESS_PRINCIPAL_ID"
printf 'readiness_identity principal_type: %s\n' "$READINESS_PRINCIPAL_TYPE"
```

Use those values in the protected input:

```hcl
readiness_identity = {
  tenant_id      = "<READINESS_TENANT_ID>"
  principal_id   = "<READINESS_PRINCIPAL_ID>"
  principal_type = "User"
}
```

For a service-principal login, `az account show --query user.name` is normally the application
(client) ID. Resolve it to the service principal's Entra object ID:

```bash
export READINESS_CLIENT_ID="$(
  az account show --query user.name --output tsv
)"
export READINESS_PRINCIPAL_ID="$(
  az ad sp show \
    --id "$READINESS_CLIENT_ID" \
    --query id \
    --output tsv
)"
export READINESS_PRINCIPAL_TYPE="ServicePrincipal"
```

Do not use the application/client ID as `principal_id`. Do not substitute the operator-group,
tenant, or subscription ID. If either directory lookup is denied, obtain the object ID through the
approved Entra administration path and verify that it identifies the same active login.

Edit `$BOOTSTRAP_TFVARS` with approved values from
[`backend-inputs.md`](../specs/003-terraform-backend-bootstrap/contracts/backend-inputs.md).
Set `source_commit` to `$SOURCE_COMMIT` and set `readiness_identity` to the active identity
resolved above. Do not add a storage key, SAS, access token, password, or certificate.

Verify the ignored backend overrides before creating them:

```bash
git check-ignore -v \
  terraform/bootstrap/backend.local.tf \
  terraform/bootstrap/backend.azurerm.tf
```

Initialize the bootstrap root with protected local state:

```bash
cp terraform/bootstrap/backend.local.tf.example \
  terraform/bootstrap/backend.local.tf

terraform -chdir=terraform/bootstrap init \
  -reconfigure \
  -backend-config="path=$BOOTSTRAP_LOCAL_STATE"

terraform -chdir=terraform/bootstrap validate
```

The state file is created by the first state-writing Terraform operation. After creation, require
mode `0600`. The state file and recognized sibling backups remain under `/state`, never
`/evidence`.

## A3. Create, review, approve, and apply the backend plan

```bash
export BOOTSTRAP_CREATE_PLAN="$BOOTSTRAP_STATE_DIR/create.tfplan"
export BOOTSTRAP_CREATE_DIGEST="$BOOTSTRAP_STATE_DIR/create.tfplan.sha256"
export BOOTSTRAP_CREATE_APPROVAL="$BOOTSTRAP_STATE_DIR/create-approval.json"

terraform -chdir=terraform/bootstrap plan \
  -input=false \
  -var-file="$BOOTSTRAP_TFVARS" \
  -out="$BOOTSTRAP_CREATE_PLAN"

tee_output "$BOOTSTRAP_CREATE_DIGEST" \
  sha256sum "$BOOTSTRAP_CREATE_PLAN"
tee_output "$BOOTSTRAP_STATE_DIR/bootstrap.tfvars.sha256" \
  sha256sum "$BOOTSTRAP_TFVARS"
chmod 0600 "$BOOTSTRAP_CREATE_PLAN" "$BOOTSTRAP_CREATE_DIGEST"

terraform -chdir=terraform/bootstrap show -no-color "$BOOTSTRAP_CREATE_PLAN"
```

Review the plan interactively; do not copy its raw output into evidence. For managed mode, confirm:

- only pinned resource-group and storage-account AVMs are called;
- generated names match the approved ALZ components;
- the container is private and shared-key and anonymous access are disabled;
- network rules match the selected mode exactly;
- operator-group and optional workload-identity roles are container-scoped;
- versioning, seven-day soft delete, encryption, TLS, HTTPS, tags, and the lock are present;
- no secret, unexpected replacement, or unrelated resource appears.

For existing mode, confirm that the plan creates, imports, mutates, locks, and deletes nothing.

After plan generation, create `$BOOTSTRAP_CREATE_APPROVAL` to match
[`backend-plan-approval.schema.json`](../specs/003-terraform-backend-bootstrap/contracts/backend-plan-approval.schema.json).
Its `action` is `create`; its source, input, and plan digests must match the current files. An
authorized reviewer supplies `approved_at` and `approval_reference`.

Only after the reviewer approves the displayed plan, create the protected approval record:

```bash
read -r -p "Authorized approval reference: " APPROVAL_REFERENCE
test -n "$APPROVAL_REFERENCE"
```

If the prompt returns EOF or the reference is empty, stop without running the next block. Then bind
the approval to the current source and exact plan:

```bash
test "$SOURCE_COMMIT" = "$(git rev-parse HEAD)"

export PLAN_CREATED_AT="$(
  date -u \
    -r "$BOOTSTRAP_CREATE_PLAN" \
    +%Y-%m-%dT%H:%M:%SZ
)"
export APPROVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export BOOTSTRAP_CREATE_APPROVAL_TMP="$BOOTSTRAP_CREATE_APPROVAL.tmp"

jq -n \
  --arg source_commit "$SOURCE_COMMIT" \
  --arg input_digest "$(
    sha256sum "$BOOTSTRAP_TFVARS" |
    awk '{print $1}'
  )" \
  --arg plan_digest "$(
    sha256sum "$BOOTSTRAP_CREATE_PLAN" |
    awk '{print $1}'
  )" \
  --arg plan_created_at "$PLAN_CREATED_AT" \
  --arg approved_at "$APPROVED_AT" \
  --arg approval_reference "$APPROVAL_REFERENCE" \
  '{
    schema_version: "1.0",
    action: "create",
    source_commit: $source_commit,
    input_digest: $input_digest,
    plan_digest: $plan_digest,
    plan_created_at: $plan_created_at,
    approved_at: $approved_at,
    approval_reference: $approval_reference
  }' >"$BOOTSTRAP_CREATE_APPROVAL_TMP"

chmod 0600 "$BOOTSTRAP_CREATE_APPROVAL_TMP"
mv "$BOOTSTRAP_CREATE_APPROVAL_TMP" "$BOOTSTRAP_CREATE_APPROVAL"
jq . "$BOOTSTRAP_CREATE_APPROVAL"
```

Generating this JSON does not itself approve the plan. `APPROVAL_REFERENCE` must identify the
authorized review that already approved the exact displayed plan and digest. Keep the approval
record under `/state`; do not copy it into evidence.

Immediately before apply:

```bash
sha256sum -c "$BOOTSTRAP_CREATE_DIGEST"

test "$(jq -r '.source_commit' "$BOOTSTRAP_CREATE_APPROVAL")" = "$SOURCE_COMMIT"
test "$(jq -r '.input_digest' "$BOOTSTRAP_CREATE_APPROVAL")" = \
  "$(sha256sum "$BOOTSTRAP_TFVARS" | awk '{print $1}')"
test "$(jq -r '.plan_digest' "$BOOTSTRAP_CREATE_APPROVAL")" = \
  "$(sha256sum "$BOOTSTRAP_CREATE_PLAN" | awk '{print $1}')"

terraform -chdir=terraform/bootstrap apply \
  -input=false \
  "$BOOTSTRAP_CREATE_PLAN"
BOOTSTRAP_APPLIED_EPOCH="$(date +%s)"

test "$(stat -c '%a' "$BOOTSTRAP_LOCAL_STATE")" = "600"
```

Terraform must also accept the saved plan's state snapshot as current. A changed digest or stale
plan blocks apply; never regenerate a plan after approval.

Create a second plan and require `-detailed-exitcode` status `0`:

```bash
set +e
terraform -chdir=terraform/bootstrap plan \
  -input=false \
  -var-file="$BOOTSTRAP_TFVARS" \
  -detailed-exitcode \
  -no-color 2>&1 |
  tee "$BOOTSTRAP_STATE_DIR/create-no-change.log"
BOOTSTRAP_NO_CHANGE_PIPE_STATUSES=("${PIPESTATUS[@]}")
BOOTSTRAP_NO_CHANGE_STATUS="${BOOTSTRAP_NO_CHANGE_PIPE_STATUSES[0]}"
set +e
test "$BOOTSTRAP_NO_CHANGE_STATUS" -eq 0
test "${BOOTSTRAP_NO_CHANGE_PIPE_STATUSES[1]}" -eq 0
```

Display the captured status and record a bounded, secret-free result plus the protected log's
digest:

```bash
printf 'Terraform detailed exit code: %s\n' \
  "$BOOTSTRAP_NO_CHANGE_STATUS"

test "$BOOTSTRAP_NO_CHANGE_STATUS" -eq 0
test "$SOURCE_COMMIT" = "$(git rev-parse HEAD)"

export BOOTSTRAP_NO_CHANGE_OBSERVED_AT="$(
  date -u +%Y-%m-%dT%H:%M:%SZ
)"
export BOOTSTRAP_NO_CHANGE_LOG="$BOOTSTRAP_STATE_DIR/create-no-change.log"

tee_output \
  "$BACKEND_EVIDENCE_DIR/bootstrap-create-no-change.json" \
  jq -n \
    --arg source_commit "$SOURCE_COMMIT" \
    --arg observed_at "$BOOTSTRAP_NO_CHANGE_OBSERVED_AT" \
    --arg log_digest "$(
      sha256sum "$BOOTSTRAP_NO_CHANGE_LOG" |
      awk '{print $1}'
    )" \
    --argjson exit_code "$BOOTSTRAP_NO_CHANGE_STATUS" \
    '{
      schema_version: "1.0",
      command_id: "terraform_bootstrap_create_no_change",
      source_commit: $source_commit,
      observed_at: $observed_at,
      exit_code: $exit_code,
      no_changes: ($exit_code == 0),
      protected_log_sha256: $log_digest
    }'

jq -e \
  '.exit_code == 0 and
   .no_changes == true and
   (.protected_log_sha256 | test("^[a-f0-9]{64}$"))' \
  "$BACKEND_EVIDENCE_DIR/bootstrap-create-no-change.json"
```

Do not copy the raw no-change log into evidence. Keep it under `/state`; only the bounded result
and digest belong under `/evidence`.

## A4. Export canonical coordinates

```bash
tee_output "$BACKEND_EVIDENCE_DIR/backend-coordinates.json" \
  terraform -chdir=terraform/bootstrap output -json backend_coordinates

tee_output "$BACKEND_EVIDENCE_DIR/backend-coordinates.json.sha256" \
  sha256sum "$BACKEND_EVIDENCE_DIR/backend-coordinates.json"

export COORDINATES_DOCUMENT_DIGEST="$(
  sha256sum "$BACKEND_EVIDENCE_DIR/backend-coordinates.json" |
  awk '{print $1}'
)"
export COORDINATES_DIGEST="$(
  jq -jc . "$BACKEND_EVIDENCE_DIR/backend-coordinates.json" |
  sha256sum |
  awk '{print $1}'
)"
export TERRAFORM_COORDINATES_DIGEST="$(
  printf 'local.coordinates_digest\n' |
  terraform -chdir=terraform/bootstrap console \
    -var-file="$BOOTSTRAP_TFVARS" |
  tr -d '"'
)"

test "$COORDINATES_DIGEST" = "$TERRAFORM_COORDINATES_DIGEST"
```

Validate the live output and record a bounded result:

```bash
export BACKEND_COORDINATES_FILE="$BACKEND_EVIDENCE_DIR/backend-coordinates.json"
export BACKEND_COORDINATES_SCHEMA="$PWD/specs/003-terraform-backend-bootstrap/contracts/backend-coordinates.schema.json"

persist_run_context

sha256sum -c "$BACKEND_COORDINATES_FILE.sha256"
test "$SOURCE_COMMIT" = "$(git rev-parse HEAD)"

jq -e \
  --arg environment "$BACKEND_ENVIRONMENT" \
  '.state_keys.bootstrap == ($environment + "/bootstrap.tfstate") and
   .state_keys.main == ($environment + "/main.tfstate") and
   .state_keys.capacity_probe == ($environment + "/capacity-probe.tfstate") and
   ([.state_keys[]] | unique | length) == 3' \
  "$BACKEND_COORDINATES_FILE" >/dev/null

.venv/bin/python - \
  "$BACKEND_COORDINATES_FILE" \
  "$BACKEND_COORDINATES_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

coordinates_path = Path(sys.argv[1])
schema_path = Path(sys.argv[2])
coordinates = json.loads(coordinates_path.read_text())
schema = json.loads(schema_path.read_text())
Draft202012Validator(
    schema,
    format_checker=FormatChecker(),
).validate(coordinates)
PY

export COORDINATES_VALIDATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

tee_output \
  "$BACKEND_EVIDENCE_DIR/backend-coordinates-validation.json" \
  jq -n \
    --arg source_commit "$SOURCE_COMMIT" \
    --arg observed_at "$COORDINATES_VALIDATED_AT" \
    --arg document_digest "$COORDINATES_DOCUMENT_DIGEST" \
    --arg schema_digest "$(
      sha256sum "$BACKEND_COORDINATES_SCHEMA" |
      awk '{print $1}'
    )" \
    '{
      schema_version: "1.0",
      command_id: "backend_coordinates_schema_validation",
      source_commit: $source_commit,
      observed_at: $observed_at,
      document_sha256: $document_digest,
      schema_sha256: $schema_digest,
      state_keys_exact_and_distinct: true,
      valid: true
    }'

jq -e \
  '.valid == true and
   .state_keys_exact_and_distinct == true and
   (.document_sha256 | test("^[a-f0-9]{64}$")) and
   (.schema_sha256 | test("^[a-f0-9]{64}$"))' \
  "$BACKEND_EVIDENCE_DIR/backend-coordinates-validation.json"
```

`make backend-contract-test` validates repository contract fixtures; the commands above separately
validate the live coordinates exported for this run. Keep all three secret-free A4 artifacts in
evidence:

```text
backend-coordinates.json
backend-coordinates.json.sha256
backend-coordinates-validation.json
```

## A5. Perform preliminary readiness from the actual runner

The commands in this subsection cover the managed `restricted_public` path with an interactive
`User` identity. Private mode and service-principal execution require a separately approved
execution-context procedure. Do not reinterpret these commands for another mode.

Prepare protected paths and derive non-secret coordinates from the canonical A4 evidence:

```bash
export PRELIMINARY_ASSERTIONS="$BOOTSTRAP_STATE_DIR/readiness-assertions-preliminary.json"
export PRELIMINARY_TFVARS="$BOOTSTRAP_STATE_DIR/readiness-preliminary.tfvars.json"
export PRELIMINARY_PLAN="$BOOTSTRAP_STATE_DIR/readiness-preliminary.tfplan"
export PRELIMINARY_PLAN_DIGEST="$BOOTSTRAP_STATE_DIR/readiness-preliminary.tfplan.sha256"
export PRELIMINARY_INPUT_MANIFEST="$BOOTSTRAP_STATE_DIR/readiness-preliminary-inputs.json"
export PRELIMINARY_APPROVAL="$BOOTSTRAP_STATE_DIR/readiness-preliminary-approval.json"
export READINESS_ASSERTIONS_SCHEMA="$PWD/specs/003-terraform-backend-bootstrap/contracts/backend-readiness-assertions.schema.json"
export PLAN_APPROVAL_SCHEMA="$PWD/specs/003-terraform-backend-bootstrap/contracts/backend-plan-approval.schema.json"

export STORAGE_ACCOUNT_NAME="$(
  jq -er '.storage_account_name' "$BACKEND_COORDINATES_FILE"
)"
export STORAGE_ACCOUNT_RESOURCE_ID="$(
  jq -er '.resource_ids.storage_account' "$BACKEND_COORDINATES_FILE"
)"
export STATE_CONTAINER_NAME="$(
  jq -er '.container_name' "$BACKEND_COORDINATES_FILE"
)"
export BLOB_HOST="$STORAGE_ACCOUNT_NAME.blob.core.windows.net"

test "$(jq -r '.network_mode' "$BACKEND_COORDINATES_FILE")" = "restricted_public"
test "$SOURCE_COMMIT" = "$(git rev-parse HEAD)"
test -n "$READINESS_PRINCIPAL_ID"

export ASSESSMENT_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

Run every observation directly. Keep raw results only in shell variables long enough to validate
and reduce them to bounded values; do not write raw output to evidence.

### A5.1 Account and active identity

```bash
export ACCOUNT_OBSERVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set +e
ACCOUNT_JSON="$(
  az account show \
    --query '{subscription_id:id,tenant_id:tenantId,user_type:user.type}' \
    --output json
)"
ACCOUNT_EXIT="$?"
set +e
test "$ACCOUNT_EXIT" -eq 0
test "$(jq -r '.subscription_id' <<<"$ACCOUNT_JSON")" = \
  "$(jq -r '.subscription_id' "$BACKEND_COORDINATES_FILE")"
test "$(jq -r '.tenant_id' <<<"$ACCOUNT_JSON")" = \
  "$(jq -r '.tenant_id' "$BACKEND_COORDINATES_FILE")"
test "$(jq -r '.user_type' <<<"$ACCOUNT_JSON")" = "user"
test "$(
  az ad signed-in-user show --query id --output tsv
)" = "$READINESS_PRINCIPAL_ID"
```

### A5.2 Storage account and container

```bash
export BACKEND_OBSERVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set +e
BACKEND_JSON="$(
  az storage account show \
    --ids "$STORAGE_ACCOUNT_RESOURCE_ID" \
    --query '{id:id,publicNetworkAccess:publicNetworkAccess,allowSharedKeyAccess:allowSharedKeyAccess}' \
    --output json
)"
BACKEND_EXIT="$?"
set +e
test "$BACKEND_EXIT" -eq 0
test "$(jq -r '.id' <<<"$BACKEND_JSON")" = "$STORAGE_ACCOUNT_RESOURCE_ID"
test "$(jq -r '.publicNetworkAccess' <<<"$BACKEND_JSON")" = "Enabled"
test "$(jq -r '.allowSharedKeyAccess' <<<"$BACKEND_JSON")" = "false"

export CONTAINER_OBSERVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set +e
CONTAINER_NAME_OBSERVED="$(
  az storage container show \
    --auth-mode login \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --name "$STATE_CONTAINER_NAME" \
    --query name \
    --output tsv
)"
CONTAINER_EXIT="$?"
set +e
test "$CONTAINER_EXIT" -eq 0
test "$CONTAINER_NAME_OBSERVED" = "$STATE_CONTAINER_NAME"
```

If the container lookup fails immediately after role creation, stop the assessment, record the
role-propagation interval separately, refresh Azure authentication, and begin a new assessment.
Do not label a failed authorization command as passed.

### A5.3 DNS and network reachability

```bash
export DNS_OBSERVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set +e
DNS_OUTPUT="$(getent ahostsv4 "$BLOB_HOST")"
DNS_EXIT="$?"
set +e
test "$DNS_EXIT" -eq 0

export RESOLVED_BLOB_IPV4_JSON="$(
  awk '{print $1}' <<<"$DNS_OUTPUT" |
    sort -u |
    jq -R . |
    jq -s .
)"
test "$(jq 'length' <<<"$RESOLVED_BLOB_IPV4_JSON")" -gt 0

export NETWORK_OBSERVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export NETWORK_HEADER_FILE="$BOOTSTRAP_STATE_DIR/blob-network-headers.txt"
set +e
NETWORK_HTTP_STATUS="$(
  curl --ipv4 \
    --silent \
    --show-error \
    --head \
    --dump-header "$NETWORK_HEADER_FILE" \
    --output /dev/null \
    --write-out '%{http_code}' \
    "https://$BLOB_HOST/$STATE_CONTAINER_NAME?restype=container"
)"
NETWORK_EXIT="$?"
set +e
chmod 0600 "$NETWORK_HEADER_FILE"
test "$NETWORK_EXIT" -eq 0
case "$NETWORK_HTTP_STATUS" in
  200|400|401|403)
    export NETWORK_OBSERVED_VALUE="http_status=$NETWORK_HTTP_STATUS"
    ;;
  409)
    if tr -d '\r' <"$NETWORK_HEADER_FILE" |
      grep -Eiq \
        '^HTTP/[0-9.]+ 409 Public access is not permitted on this storage account\.?$'; then
      export NETWORK_OBSERVED_VALUE="http_status=409_public_access_not_permitted"
    else
      printf 'HTTP 409 did not contain the required public-access prohibition reason.\n' >&2
      false
    fi
    ;;
  *) printf 'Unexpected Blob HTTP status: %s\n' "$NETWORK_HTTP_STATUS" >&2; false ;;
esac
```

An unauthenticated HTTP `403` is acceptable for the network check because it proves the private
container endpoint is reachable. HTTP `409` is acceptable only when the response reason is exactly
`Public access is not permitted on this storage account`; that response proves the selected
endpoint is reachable and the configured anonymous-public-access prohibition is active. The
authenticated Blob command below separately proves authorization. Any other `409`, HTTP `000`,
DNS failure, timeout, or transport failure blocks readiness. Keep the raw headers under `/state`,
not `/evidence`.

### A5.4 Blob authorization and state-key separation

```bash
export AUTHORIZATION_OBSERVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set +e
BLOB_RESULT_COUNT="$(
  az storage blob list \
    --auth-mode login \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --container-name "$STATE_CONTAINER_NAME" \
    --num-results 1 \
    --query 'length(@)' \
    --output tsv
)"
AUTHORIZATION_EXIT="$?"
set +e
test "$AUTHORIZATION_EXIT" -eq 0
case "$BLOB_RESULT_COUNT" in
  0|1) ;;
  *) printf 'Unexpected Blob query count: %s\n' "$BLOB_RESULT_COUNT" >&2; false ;;
esac
```

If authorization failed or returned an unexpected count, stop without running the next block:

```bash
export KEY_SEPARATION_OBSERVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set +e
jq -e \
  --arg environment "$BACKEND_ENVIRONMENT" \
  '.state_keys.bootstrap == ($environment + "/bootstrap.tfstate") and
   .state_keys.main == ($environment + "/main.tfstate") and
   .state_keys.capacity_probe == ($environment + "/capacity-probe.tfstate") and
   ([.state_keys[]] | unique | length) == 3' \
  "$BACKEND_COORDINATES_FILE" >/dev/null
KEY_SEPARATION_EXIT="$?"
set +e
test "$KEY_SEPARATION_EXIT" -eq 0
```

### A5.5 Bind the actual runner context

Use the same approved external-source method used to prepare the restricted-public firewall input:

```bash
export PUBLIC_SOURCE_IPV4="$(
  curl --ipv4 --fail --silent --show-error https://api.ipify.org
)"

export RUNNER_CONTEXT_JSON="$(
  jq -cnS \
    --arg subscription_id "$(jq -r '.subscription_id' "$BACKEND_COORDINATES_FILE")" \
    --arg tenant_id "$(jq -r '.tenant_id' "$BACKEND_COORDINATES_FILE")" \
    --arg principal_id "$READINESS_PRINCIPAL_ID" \
    --arg network_mode "restricted_public" \
    --arg public_source_ipv4 "$PUBLIC_SOURCE_IPV4" \
    --argjson resolved_blob_ipv4_addresses "$RESOLVED_BLOB_IPV4_JSON" \
    '{
      subscription_id: $subscription_id,
      tenant_id: $tenant_id,
      principal_id: $principal_id,
      network_mode: $network_mode,
      observed_public_source_ipv4: $public_source_ipv4,
      resolved_blob_ipv4_addresses: $resolved_blob_ipv4_addresses
    }'
)"

export RUNNER_CONTEXT_DIGEST="$(
  printf '%s' "$RUNNER_CONTEXT_JSON" |
    sha256sum |
    awk '{print $1}'
)"
export ASSESSMENT_COMPLETED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

Changing the identity, public source address, route, or resolved endpoint invalidates this
assessment.

### A5.6 Create and validate protected assertions

The exact stable command IDs are:

| Check | Command ID |
|---|---|
| Account context | `az_account_show` |
| Storage account | `az_storage_account_show` |
| Container | `az_storage_container_show` |
| DNS | `getent_blob_endpoint` |
| Network | `curl_blob_endpoint` |
| Authorization | `az_storage_blob_list` |
| Key separation | `terraform_coordinate_check` |
| Migration | `terraform_state_pull` |
| Locking | `terraform_lock_conflict` |

Create the protected assertions atomically. Preliminary readiness records only migration and
locking as `not_run`:

```bash
export PRELIMINARY_ASSERTIONS_TMP="$PRELIMINARY_ASSERTIONS.tmp"

jq -n \
  --arg source_commit "$SOURCE_COMMIT" \
  --arg coordinates_digest "$COORDINATES_DIGEST" \
  --arg assessment_started_at "$ASSESSMENT_STARTED_AT" \
  --arg assessment_completed_at "$ASSESSMENT_COMPLETED_AT" \
  --arg runner_context_digest "$RUNNER_CONTEXT_DIGEST" \
  --arg public_source_ipv4 "$PUBLIC_SOURCE_IPV4" \
  --argjson resolved_blob_ipv4_addresses "$RESOLVED_BLOB_IPV4_JSON" \
  --arg account_observed_at "$ACCOUNT_OBSERVED_AT" \
  --argjson account_exit "$ACCOUNT_EXIT" \
  --arg backend_observed_at "$BACKEND_OBSERVED_AT" \
  --argjson backend_exit "$BACKEND_EXIT" \
  --arg container_observed_at "$CONTAINER_OBSERVED_AT" \
  --argjson container_exit "$CONTAINER_EXIT" \
  --arg dns_observed_at "$DNS_OBSERVED_AT" \
  --argjson dns_exit "$DNS_EXIT" \
  --argjson resolved_count "$(jq 'length' <<<"$RESOLVED_BLOB_IPV4_JSON")" \
  --arg network_observed_at "$NETWORK_OBSERVED_AT" \
  --argjson network_exit "$NETWORK_EXIT" \
  --arg network_observed_value "$NETWORK_OBSERVED_VALUE" \
  --arg authorization_observed_at "$AUTHORIZATION_OBSERVED_AT" \
  --argjson authorization_exit "$AUTHORIZATION_EXIT" \
  --arg blob_result_count "$BLOB_RESULT_COUNT" \
  --arg key_observed_at "$KEY_SEPARATION_OBSERVED_AT" \
  --argjson key_exit "$KEY_SEPARATION_EXIT" \
  '{
    schema_version: "1.0",
    source_commit: $source_commit,
    coordinates_digest: $coordinates_digest,
    assessment_started_at: $assessment_started_at,
    assessment_completed_at: $assessment_completed_at,
    execution_context: {
      network_mode: "restricted_public",
      runner_context_digest: $runner_context_digest,
      observed_public_source_ipv4: $public_source_ipv4,
      private_network_context_digest: null,
      resolved_blob_ipv4_addresses: $resolved_blob_ipv4_addresses,
      observed_at: $assessment_completed_at
    },
    checks: {
      account_context: {
        command_id: "az_account_show",
        observed_at: $account_observed_at,
        exit_code: $account_exit,
        status: "passed",
        observed_value: "subscription_tenant_identity_match"
      },
      backend_exists: {
        command_id: "az_storage_account_show",
        observed_at: $backend_observed_at,
        exit_code: $backend_exit,
        status: "passed",
        observed_value: "account_present_public_enabled_shared_key_disabled"
      },
      container_exists: {
        command_id: "az_storage_container_show",
        observed_at: $container_observed_at,
        exit_code: $container_exit,
        status: "passed",
        observed_value: "container_name_match"
      },
      dns: {
        command_id: "getent_blob_endpoint",
        observed_at: $dns_observed_at,
        exit_code: $dns_exit,
        status: "passed",
        observed_value: ("resolved_ipv4_count=" + ($resolved_count | tostring))
      },
      network: {
        command_id: "curl_blob_endpoint",
        observed_at: $network_observed_at,
        exit_code: $network_exit,
        status: "passed",
        observed_value: $network_observed_value
      },
      authorization: {
        command_id: "az_storage_blob_list",
        observed_at: $authorization_observed_at,
        exit_code: $authorization_exit,
        status: "passed",
        observed_value: ("blob_query_count=" + $blob_result_count)
      },
      state_key_separation: {
        command_id: "terraform_coordinate_check",
        observed_at: $key_observed_at,
        exit_code: $key_exit,
        status: "passed",
        observed_value: "three_exact_pairwise_distinct_keys"
      },
      migration: {
        command_id: "terraform_state_pull",
        observed_at: $assessment_completed_at,
        exit_code: null,
        status: "not_run",
        observed_value: ""
      },
      locking: {
        command_id: "terraform_lock_conflict",
        observed_at: $assessment_completed_at,
        exit_code: null,
        status: "not_run",
        observed_value: ""
      }
    }
  }' >"$PRELIMINARY_ASSERTIONS_TMP"

chmod 0600 "$PRELIMINARY_ASSERTIONS_TMP"
mv "$PRELIMINARY_ASSERTIONS_TMP" "$PRELIMINARY_ASSERTIONS"

.venv/bin/python - \
  "$PRELIMINARY_ASSERTIONS" \
  "$READINESS_ASSERTIONS_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

assertions = json.loads(Path(sys.argv[1]).read_text())
schema = json.loads(Path(sys.argv[2]).read_text())
Draft202012Validator(
    schema,
    format_checker=FormatChecker(),
).validate(assertions)
PY
```

The assertions file is protected Terraform input and remains under `/state`; do not copy it into
evidence.

### A5.7 Create and approve the preliminary output plan

Wrap the assertions in a protected JSON variable file:

```bash
export PRELIMINARY_TFVARS_TMP="$PRELIMINARY_TFVARS.tmp"

jq -n \
  --slurpfile assertions "$PRELIMINARY_ASSERTIONS" \
  '{
    readiness_phase: "preliminary",
    readiness_assertions: $assertions[0]
  }' >"$PRELIMINARY_TFVARS_TMP"

chmod 0600 "$PRELIMINARY_TFVARS_TMP"
mv "$PRELIMINARY_TFVARS_TMP" "$PRELIMINARY_TFVARS"
```

Create the exact output-only plan and protected input manifest:

```bash
terraform -chdir=terraform/bootstrap plan \
  -input=false \
  -var-file="$BOOTSTRAP_TFVARS" \
  -var-file="$PRELIMINARY_TFVARS" \
  -out="$PRELIMINARY_PLAN"

tee_output "$PRELIMINARY_PLAN_DIGEST" \
  sha256sum "$PRELIMINARY_PLAN"

jq -n \
  --arg bootstrap_tfvars_sha256 "$(
    sha256sum "$BOOTSTRAP_TFVARS" |
    awk '{print $1}'
  )" \
  --arg preliminary_tfvars_sha256 "$(
    sha256sum "$PRELIMINARY_TFVARS" |
    awk '{print $1}'
  )" \
  '{
    bootstrap_tfvars_sha256: $bootstrap_tfvars_sha256,
    preliminary_tfvars_sha256: $preliminary_tfvars_sha256
  }' >"$PRELIMINARY_INPUT_MANIFEST"

chmod 0600 \
  "$PRELIMINARY_PLAN" \
  "$PRELIMINARY_PLAN_DIGEST" \
  "$PRELIMINARY_INPUT_MANIFEST"

terraform -chdir=terraform/bootstrap show -no-color "$PRELIMINARY_PLAN"

export PRELIMINARY_RESOURCE_CHANGE_COUNT="$(
  terraform -chdir=terraform/bootstrap show -json "$PRELIMINARY_PLAN" |
    jq '[
      .resource_changes[]? |
      select(.change.actions != ["no-op"])
    ] | length'
)"
export PRELIMINARY_READINESS_OUTPUT_ACTIONS="$(
  terraform -chdir=terraform/bootstrap show -json "$PRELIMINARY_PLAN" |
    jq -c '.output_changes.backend_readiness.actions'
)"
export PRELIMINARY_OUTPUT_CHANGE_COUNT="$(
  terraform -chdir=terraform/bootstrap show -json "$PRELIMINARY_PLAN" |
    jq '[
      .output_changes |
      to_entries[] |
      select(.value.actions != ["no-op"])
    ] | length'
)"

test "$PRELIMINARY_RESOURCE_CHANGE_COUNT" -eq 0
test "$PRELIMINARY_READINESS_OUTPUT_ACTIONS" = '["update"]'
test "$PRELIMINARY_OUTPUT_CHANGE_COUNT" -eq 1
```

These checks reject any resource addition, update, replacement, or deletion and require the
readiness output to be the only expected update. After an authorized reviewer approves that exact
plan, create a separate protected approval record. Preliminary readiness remains part of the
managed create lifecycle, so the current approval contract uses `action = "create"`:

```bash
read -r -p "Authorized preliminary-readiness approval reference: " \
  PRELIMINARY_APPROVAL_REFERENCE
test -n "$PRELIMINARY_APPROVAL_REFERENCE"
```

If the prompt returns EOF or the reference is empty, stop without running the next block:

```bash
test "$SOURCE_COMMIT" = "$(git rev-parse HEAD)"

export PRELIMINARY_PLAN_CREATED_AT="$(
  date -u -r "$PRELIMINARY_PLAN" +%Y-%m-%dT%H:%M:%SZ
)"
export PRELIMINARY_APPROVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export PRELIMINARY_INPUT_DIGEST="$(
  sha256sum "$PRELIMINARY_INPUT_MANIFEST" |
  awk '{print $1}'
)"
export PRELIMINARY_APPROVAL_TMP="$PRELIMINARY_APPROVAL.tmp"

jq -n \
  --arg source_commit "$SOURCE_COMMIT" \
  --arg input_digest "$PRELIMINARY_INPUT_DIGEST" \
  --arg plan_digest "$(
    sha256sum "$PRELIMINARY_PLAN" |
    awk '{print $1}'
  )" \
  --arg plan_created_at "$PRELIMINARY_PLAN_CREATED_AT" \
  --arg approved_at "$PRELIMINARY_APPROVED_AT" \
  --arg approval_reference "$PRELIMINARY_APPROVAL_REFERENCE" \
  '{
    schema_version: "1.0",
    action: "create",
    source_commit: $source_commit,
    input_digest: $input_digest,
    plan_digest: $plan_digest,
    plan_created_at: $plan_created_at,
    approved_at: $approved_at,
    approval_reference: $approval_reference
  }' >"$PRELIMINARY_APPROVAL_TMP"

chmod 0600 "$PRELIMINARY_APPROVAL_TMP"
mv "$PRELIMINARY_APPROVAL_TMP" "$PRELIMINARY_APPROVAL"

.venv/bin/python - \
  "$PRELIMINARY_APPROVAL" \
  "$PLAN_APPROVAL_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

approval = json.loads(Path(sys.argv[1]).read_text())
schema = json.loads(Path(sys.argv[2]).read_text())
Draft202012Validator(
    schema,
    format_checker=FormatChecker(),
).validate(approval)
PY
```

Immediately before apply, recheck every binding and apply only the saved plan:

```bash
sha256sum -c "$PRELIMINARY_PLAN_DIGEST"
test "$(jq -r '.source_commit' "$PRELIMINARY_APPROVAL")" = "$SOURCE_COMMIT"
test "$(jq -r '.input_digest' "$PRELIMINARY_APPROVAL")" = \
  "$(sha256sum "$PRELIMINARY_INPUT_MANIFEST" | awk '{print $1}')"
test "$(jq -r '.plan_digest' "$PRELIMINARY_APPROVAL")" = \
  "$(sha256sum "$PRELIMINARY_PLAN" | awk '{print $1}')"

terraform -chdir=terraform/bootstrap apply \
  -input=false \
  "$PRELIMINARY_PLAN"
```

### A5.8 Export and validate preliminary evidence

Export the native Terraform classification and adjacent digest:

```bash
tee_output "$BACKEND_EVIDENCE_DIR/backend-readiness-preliminary.json" \
  terraform -chdir=terraform/bootstrap output -json backend_readiness

tee_output "$BACKEND_EVIDENCE_DIR/backend-readiness-preliminary.json.sha256" \
  sha256sum "$BACKEND_EVIDENCE_DIR/backend-readiness-preliminary.json"
```

Validate the exact preliminary state:

```bash
sha256sum -c \
  "$BACKEND_EVIDENCE_DIR/backend-readiness-preliminary.json.sha256"

jq -e \
  '.status == "failed" and
   .failure_class == "configuration_mismatch" and
   .checks.account_context.status == "passed" and
   .checks.backend_exists.status == "passed" and
   .checks.container_exists.status == "passed" and
   .checks.dns.status == "passed" and
   .checks.network.status == "passed" and
   .checks.authorization.status == "passed" and
   .checks.state_key_separation.status == "passed" and
   .checks.migration.status == "not_run" and
   .checks.locking.status == "not_run"' \
  "$BACKEND_EVIDENCE_DIR/backend-readiness-preliminary.json"

tee_output \
  "$BACKEND_EVIDENCE_DIR/preliminary-readiness-plan.json" \
  jq -n \
    --arg source_commit "$SOURCE_COMMIT" \
    --arg plan_digest "$(
      sha256sum "$PRELIMINARY_PLAN" |
      awk '{print $1}'
    )" \
    --arg input_digest "$PRELIMINARY_INPUT_DIGEST" \
    --arg approval_reference "$PRELIMINARY_APPROVAL_REFERENCE" \
    --arg resource_change_count "$PRELIMINARY_RESOURCE_CHANGE_COUNT" \
    --arg readiness_output_actions "$PRELIMINARY_READINESS_OUTPUT_ACTIONS" \
    --arg output_change_count "$PRELIMINARY_OUTPUT_CHANGE_COUNT" \
    --arg readiness_digest "$(
      sha256sum "$BACKEND_EVIDENCE_DIR/backend-readiness-preliminary.json" |
      awk '{print $1}'
    )" \
    '{
      schema_version: "1.0",
      stage: "preliminary_readiness",
      source_commit: $source_commit,
      plan_sha256: $plan_digest,
      input_manifest_sha256: $input_digest,
      approval_reference: $approval_reference,
      readiness_sha256: $readiness_digest,
      planned_resource_change_count: (
        $resource_change_count |
        tonumber
      ),
      readiness_output_actions: (
        $readiness_output_actions |
        fromjson
      ),
      planned_output_change_count: (
        $output_change_count |
        tonumber
      ),
      applicable_checks_passed: true,
      migration_and_locking_not_run: true
    }'
```

The top-level preliminary status is deliberately `failed/configuration_mismatch` because only
final readiness may be `ready/none`. Preliminary success is represented by all seven applicable
checks being `passed` and only migration and locking being `not_run`. Any other failed,
inconclusive, or unrun applicable check blocks A6.

## A6. Migrate bootstrap state to Azure Blob

Preserve the local state and its mode-`0600` copy until remote verification is complete:

```bash
export BOOTSTRAP_RETAINED_STATE="$BOOTSTRAP_STATE_DIR/terraform.tfstate.pre-migration"

cp --preserve=mode "$BOOTSTRAP_LOCAL_STATE" "$BOOTSTRAP_RETAINED_STATE"
chmod 0600 "$BOOTSTRAP_RETAINED_STATE"

export LOCAL_STATE_DIGEST="$(
  sha256sum "$BOOTSTRAP_RETAINED_STATE" |
  awk '{print $1}'
)"

export MIGRATION_CONTINUITY_PLAN="$BOOTSTRAP_STATE_DIR/pre-migration-continuity.tfplan"

terraform -chdir=terraform/bootstrap plan \
  -input=false \
  -refresh-only \
  -var-file="$BOOTSTRAP_TFVARS" \
  -var-file="$PRELIMINARY_TFVARS" \
  -out="$MIGRATION_CONTINUITY_PLAN"
chmod 0600 "$MIGRATION_CONTINUITY_PLAN"

export MIGRATION_CONTINUITY_RESOURCE_CHANGE_COUNT="$(
  terraform -chdir=terraform/bootstrap show -json "$MIGRATION_CONTINUITY_PLAN" |
    jq '[.resource_changes[]? | select(.change.actions != ["no-op"])] | length'
)"
test "$MIGRATION_CONTINUITY_RESOURCE_CHANGE_COUNT" -eq 0

rm terraform/bootstrap/backend.local.tf
cp terraform/bootstrap/backend.azurerm.tf.example \
  terraform/bootstrap/backend.azurerm.tf

terraform -chdir=terraform/bootstrap init \
  -migrate-state \
  -force-copy \
  -input=false \
  -backend-config="storage_account_name=<storage-account>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=$BACKEND_ENVIRONMENT/bootstrap.tfstate"
```

Use `-migrate-state`, never `-reconfigure`, when state must be copied. The noninteractive command
also requires `-force-copy`; without it Terraform cannot request migration approval and exits after
initializing an empty destination state.

Pull remote state to a protected temporary file and compare only bounded properties:

```bash
export REMOTE_STATE_COPY="$BOOTSTRAP_STATE_DIR/remote-state-verification.json"

terraform -chdir=terraform/bootstrap state pull >"$REMOTE_STATE_COPY"
chmod 0600 "$REMOTE_STATE_COPY"

LOCAL_LINEAGE="$(jq -r '.lineage' "$BOOTSTRAP_RETAINED_STATE")"
REMOTE_LINEAGE="$(jq -r '.lineage' "$REMOTE_STATE_COPY")"
LOCAL_RESOURCE_COUNT="$(jq '[.resources[]?] | length' "$BOOTSTRAP_RETAINED_STATE")"
REMOTE_RESOURCE_COUNT="$(jq '[.resources[]?] | length' "$REMOTE_STATE_COPY")"

test "$LOCAL_LINEAGE" = "$REMOTE_LINEAGE"
test "$LOCAL_RESOURCE_COUNT" -eq "$REMOTE_RESOURCE_COUNT"
```

Prove that the mechanically no-resource-change plan saved before migration remains applicable to
the same state lineage after migration:

```bash
export MIGRATION_CONTINUITY_LOG="$BOOTSTRAP_STATE_DIR/pre-migration-continuity.log"

set +e
terraform -chdir=terraform/bootstrap apply \
  -input=false \
  "$MIGRATION_CONTINUITY_PLAN" >"$MIGRATION_CONTINUITY_LOG" 2>&1
MIGRATION_CONTINUITY_STATUS="$?"
set +e

test "$MIGRATION_CONTINUITY_STATUS" -eq 0
export MIGRATION_SAVED_PLAN_CONTINUITY="true"
```

Run a remote no-change plan and retain only the protected raw log. Do not add
`-refresh-only` to this detailed-exitcode gate. A normal plan refreshes remote
objects by default, while Terraform can incorrectly return exit code `2` for an
explicit refresh-only plan whose saved JSON has zero resource and output
changes:

```bash
export REMOTE_NO_CHANGE_LOG="$BOOTSTRAP_STATE_DIR/remote-no-change.log"

set +e
terraform -chdir=terraform/bootstrap plan \
  -input=false \
  -var-file="$BOOTSTRAP_TFVARS" \
  -var-file="$PRELIMINARY_TFVARS" \
  -detailed-exitcode \
  -no-color 2>&1 |
  tee "$REMOTE_NO_CHANGE_LOG"
REMOTE_NO_CHANGE_PIPE_STATUSES=("${PIPESTATUS[@]}")
set +e

test "${REMOTE_NO_CHANGE_PIPE_STATUSES[0]}" -eq 0
test "${REMOTE_NO_CHANGE_PIPE_STATUSES[1]}" -eq 0
export REMOTE_NO_CHANGE_STATUS="${REMOTE_NO_CHANGE_PIPE_STATUSES[0]}"
export REMOTE_NO_CHANGES="true"
```

Acquire an infinite Azure Blob lease directly on the bootstrap state blob. AzureRM uses this native
lease as its state lock, so holding it makes the conflict deterministic without a timing race:

```bash
export BOOTSTRAP_STATE_KEY="$BACKEND_ENVIRONMENT/bootstrap.tfstate"
export LOCK_LEASE_ID="$(
  az storage blob lease acquire \
    --auth-mode login \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --container-name "$STATE_CONTAINER_NAME" \
    --blob-name "$BOOTSTRAP_STATE_KEY" \
    --lease-duration -1 \
    --output tsv
)"

if ! [[ "$LOCK_LEASE_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
  az storage blob lease break \
    --auth-mode login \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --container-name "$STATE_CONTAINER_NAME" \
    --blob-name "$BOOTSTRAP_STATE_KEY" \
    --lease-break-period 0 \
    --output none
  unset LOCK_LEASE_ID
  printf 'Azure CLI did not return the acquired lease UUID.\n' >&2
  false
fi
export FIRST_OPERATION_ACQUIRED="true"
```

While the native lease is held, require Terraform to reject the competing operation:

```bash
export LOCK_CONFLICT_LOG="$BOOTSTRAP_STATE_DIR/lock-conflict.log"

set +e
terraform -chdir=terraform/bootstrap plan \
  -input=false \
  -refresh-only \
  -lock-timeout=0s \
  -var-file="$BOOTSTRAP_TFVARS" \
  -var-file="$PRELIMINARY_TFVARS" \
  -out="$BOOTSTRAP_STATE_DIR/lock-contender.tfplan" \
  >"$LOCK_CONFLICT_LOG" 2>&1
LOCK_CONFLICT_STATUS="$?"
set +e

test "$LOCK_CONFLICT_STATUS" -ne 0
grep -Eiq 'state lock|already locked|lease' "$LOCK_CONFLICT_LOG"
export SECOND_OPERATION_REJECTED="true"
```

Release the exact lease, clear its protected ID, and run one more plan to prove immediate lock
acquisition and release by Terraform:

```bash
az storage blob lease release \
  --auth-mode login \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --container-name "$STATE_CONTAINER_NAME" \
  --blob-name "$BOOTSTRAP_STATE_KEY" \
  --lease-id "$LOCK_LEASE_ID" \
  --output none
unset LOCK_LEASE_ID
export FIRST_OPERATION_RELEASED="true"

terraform -chdir=terraform/bootstrap plan \
  -input=false \
  -refresh-only \
  -lock-timeout=30s \
  -var-file="$BOOTSTRAP_TFVARS" \
  -var-file="$PRELIMINARY_TFVARS" \
  -out="$BOOTSTRAP_STATE_DIR/lock-release-check.tfplan"
```

Record the migration result in a secret-free document matching
[`backend-migration-acceptance.schema.json`](../specs/003-terraform-backend-bootstrap/contracts/backend-migration-acceptance.schema.json).
Create and validate that bounded evidence:

```bash
export MIGRATION_EVIDENCE="$BACKEND_EVIDENCE_DIR/backend-migration-acceptance.json"
export MIGRATION_SCHEMA="$PWD/specs/003-terraform-backend-bootstrap/contracts/backend-migration-acceptance.schema.json"

jq -n \
  --arg source_commit "$SOURCE_COMMIT" \
  --arg observed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg coordinates_digest "$COORDINATES_DIGEST" \
  --arg local_lineage "$LOCAL_LINEAGE" \
  --argjson local_count "$LOCAL_RESOURCE_COUNT" \
  --arg local_digest "$LOCAL_STATE_DIGEST" \
  --arg remote_lineage "$REMOTE_LINEAGE" \
  --argjson remote_count "$REMOTE_RESOURCE_COUNT" \
  --arg bootstrap_key "$BACKEND_ENVIRONMENT/bootstrap.tfstate" \
  --argjson no_change_status "$REMOTE_NO_CHANGE_STATUS" \
  --argjson continuity_status "$MIGRATION_CONTINUITY_STATUS" \
  --arg main_key "$BACKEND_ENVIRONMENT/main.tfstate" \
  --arg probe_key "$BACKEND_ENVIRONMENT/capacity-probe.tfstate" \
  '{
    schema_version: "1.0",
    source_commit: $source_commit,
    observed_at: $observed_at,
    coordinates_digest: $coordinates_digest,
    local_state: {
      path_class: "protected_state_volume",
      mode: "0600",
      lineage: $local_lineage,
      resource_count: $local_count,
      digest: $local_digest,
      retained_until_verified: true,
      named_files_absent_after_deletion: false
    },
    remote_state: {
      pull_succeeded: true,
      lineage: $remote_lineage,
      resource_count: $remote_count,
      key: $bootstrap_key
    },
    lineage_matches: ($local_lineage == $remote_lineage),
    resource_count_matches: ($local_count == $remote_count),
    no_change_plan: {
      exit_code: $no_change_status,
      result: true
    },
    saved_plan_continuity: {
      exit_code: $continuity_status,
      result: true
    },
    lock_conflict: {
      first_operation_acquired: true,
      first_operation_released: true,
      second_operation_rejected: true
    },
    namespaces: {
      bootstrap: $bootstrap_key,
      main: $main_key,
      capacity_probe: $probe_key,
      pairwise_distinct: true,
      isolation_verified: true
    },
    verification_status: "failed"
  }' >"$MIGRATION_EVIDENCE"

.venv/bin/python - "$MIGRATION_EVIDENCE" "$MIGRATION_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

evidence = json.loads(Path(sys.argv[1]).read_text())
schema = json.loads(Path(sys.argv[2]).read_text())
Draft202012Validator(
    schema,
    format_checker=FormatChecker(),
).validate(evidence)
PY
```

After all checks pass, delete only the named local state files:

```bash
rm "$BOOTSTRAP_RETAINED_STATE"
rm -f "$BOOTSTRAP_LOCAL_STATE"
rm -f "$BOOTSTRAP_STATE_DIR/terraform.tfstate.backup"

find "$BOOTSTRAP_STATE_DIR" -maxdepth 1 \
  -type f \
  -name 'terraform.tfstate.*.backup' \
  -print
```

Review any timestamped backup paths before deleting those exact named files. Do not use a broad
recursive deletion. Confirm the recognized local state files are absent, then finalize migration
evidence:

```bash
test ! -e "$BOOTSTRAP_RETAINED_STATE"
test ! -e "$BOOTSTRAP_LOCAL_STATE"
test ! -e "$BOOTSTRAP_STATE_DIR/terraform.tfstate.backup"

jq \
  '.local_state.named_files_absent_after_deletion = true |
   .verification_status = "passed"' \
  "$MIGRATION_EVIDENCE" >"$MIGRATION_EVIDENCE.tmp"
mv "$MIGRATION_EVIDENCE.tmp" "$MIGRATION_EVIDENCE"

.venv/bin/python - "$MIGRATION_EVIDENCE" "$MIGRATION_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

evidence = json.loads(Path(sys.argv[1]).read_text())
schema = json.loads(Path(sys.argv[2]).read_text())
Draft202012Validator(
    schema,
    format_checker=FormatChecker(),
).validate(evidence)
PY

tee_output "$MIGRATION_EVIDENCE.sha256" \
  sha256sum "$MIGRATION_EVIDENCE"
```

## A7. Produce final readiness

Recalculate the current runner context and require it to match the preliminary assessment:

```bash
export FINAL_PUBLIC_SOURCE_IPV4="$(
  curl --ipv4 --fail --silent --show-error https://api.ipify.org
)"
export FINAL_RESOLVED_BLOB_IPV4_JSON="$(
  getent ahostsv4 "$BLOB_HOST" |
    awk '{print $1}' |
    sort -u |
    jq -R . |
    jq -s .
)"
export FINAL_RUNNER_CONTEXT_JSON="$(
  jq -cnS \
    --arg subscription_id "$(jq -r '.subscription_id' "$BACKEND_COORDINATES_FILE")" \
    --arg tenant_id "$(jq -r '.tenant_id' "$BACKEND_COORDINATES_FILE")" \
    --arg principal_id "$READINESS_PRINCIPAL_ID" \
    --arg network_mode "restricted_public" \
    --arg public_source_ipv4 "$FINAL_PUBLIC_SOURCE_IPV4" \
    --argjson resolved_blob_ipv4_addresses "$FINAL_RESOLVED_BLOB_IPV4_JSON" \
    '{
      subscription_id: $subscription_id,
      tenant_id: $tenant_id,
      principal_id: $principal_id,
      network_mode: $network_mode,
      observed_public_source_ipv4: $public_source_ipv4,
      resolved_blob_ipv4_addresses: $resolved_blob_ipv4_addresses
    }'
)"
export FINAL_RUNNER_CONTEXT_DIGEST="$(
  printf '%s' "$FINAL_RUNNER_CONTEXT_JSON" |
    sha256sum |
    awk '{print $1}'
)"

test "$FINAL_RUNNER_CONTEXT_DIGEST" = \
  "$(jq -r '.execution_context.runner_context_digest' "$PRELIMINARY_ASSERTIONS")"
```

Create final protected assertions from the validated preliminary assertions:

```bash
export FINAL_ASSERTIONS="$BOOTSTRAP_STATE_DIR/readiness-assertions-final.json"
export FINAL_TFVARS="$BOOTSTRAP_STATE_DIR/readiness-final.tfvars.json"
export FINAL_OBSERVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

jq \
  --arg observed_at "$FINAL_OBSERVED_AT" \
  '.assessment_completed_at = $observed_at |
   .execution_context.observed_at = $observed_at |
   .checks.migration = {
     command_id: "terraform_state_pull",
     observed_at: $observed_at,
     exit_code: 0,
     status: "passed",
     observed_value: "lineage_resource_count_no_change_verified"
   } |
   .checks.locking = {
     command_id: "terraform_lock_conflict",
     observed_at: $observed_at,
     exit_code: 0,
     status: "passed",
     observed_value: "native_lock_conflict_and_release_verified"
   }' \
  "$PRELIMINARY_ASSERTIONS" >"$FINAL_ASSERTIONS"
chmod 0600 "$FINAL_ASSERTIONS"

.venv/bin/python - "$FINAL_ASSERTIONS" "$READINESS_ASSERTIONS_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

assertions = json.loads(Path(sys.argv[1]).read_text())
schema = json.loads(Path(sys.argv[2]).read_text())
Draft202012Validator(
    schema,
    format_checker=FormatChecker(),
).validate(assertions)
PY

jq -n \
  --slurpfile assertions "$FINAL_ASSERTIONS" \
  '{
    readiness_phase: "final",
    readiness_assertions: $assertions[0]
  }' >"$FINAL_TFVARS"
chmod 0600 "$FINAL_TFVARS"
```

Generate and mechanically restrict the final plan to one readiness-output update:

```bash
export FINAL_PLAN="$BOOTSTRAP_STATE_DIR/readiness-final.tfplan"
export FINAL_PLAN_DIGEST="$BOOTSTRAP_STATE_DIR/readiness-final.tfplan.sha256"
export FINAL_INPUT_MANIFEST="$BOOTSTRAP_STATE_DIR/readiness-final-inputs.json"
export FINAL_APPROVAL="$BOOTSTRAP_STATE_DIR/readiness-final-approval.json"

terraform -chdir=terraform/bootstrap plan \
  -input=false \
  -var-file="$BOOTSTRAP_TFVARS" \
  -var-file="$FINAL_TFVARS" \
  -out="$FINAL_PLAN"

sha256sum "$FINAL_PLAN" >"$FINAL_PLAN_DIGEST"
chmod 0600 "$FINAL_PLAN" "$FINAL_PLAN_DIGEST"

jq -n \
  --arg bootstrap_tfvars_sha256 "$(
    sha256sum "$BOOTSTRAP_TFVARS" | awk '{print $1}'
  )" \
  --arg final_tfvars_sha256 "$(
    sha256sum "$FINAL_TFVARS" | awk '{print $1}'
  )" \
  '{
    bootstrap_tfvars_sha256: $bootstrap_tfvars_sha256,
    final_tfvars_sha256: $final_tfvars_sha256
  }' >"$FINAL_INPUT_MANIFEST"
chmod 0600 "$FINAL_INPUT_MANIFEST"

export FINAL_RESOURCE_CHANGE_COUNT="$(
  terraform -chdir=terraform/bootstrap show -json "$FINAL_PLAN" |
    jq '[.resource_changes[]? | select(.change.actions != ["no-op"])] | length'
)"
export FINAL_OUTPUT_CHANGE_COUNT="$(
  terraform -chdir=terraform/bootstrap show -json "$FINAL_PLAN" |
    jq '[.output_changes | to_entries[] | select(.value.actions != ["no-op"])] | length'
)"
export FINAL_READINESS_ACTIONS="$(
  terraform -chdir=terraform/bootstrap show -json "$FINAL_PLAN" |
    jq -c '.output_changes.backend_readiness.actions'
)"

test "$FINAL_RESOURCE_CHANGE_COUNT" -eq 0
test "$FINAL_OUTPUT_CHANGE_COUNT" -eq 1
test "$FINAL_READINESS_ACTIONS" = '["update"]'
terraform -chdir=terraform/bootstrap show -no-color "$FINAL_PLAN"
```

After an authorized reviewer approves that exact plan, create and validate its separate protected
approval record. The current approval contract uses `action = "create"` for readiness output plans
within the managed-create lifecycle:

```bash
read -r -p "Authorized final-readiness approval reference: " \
  FINAL_APPROVAL_REFERENCE
test -n "$FINAL_APPROVAL_REFERENCE"
```

If the prompt returns EOF or the reference is empty, stop without running the next block:

```bash
jq -n \
  --arg source_commit "$SOURCE_COMMIT" \
  --arg input_digest "$(
    sha256sum "$FINAL_INPUT_MANIFEST" | awk '{print $1}'
  )" \
  --arg plan_digest "$(
    sha256sum "$FINAL_PLAN" | awk '{print $1}'
  )" \
  --arg plan_created_at "$(
    date -u -r "$FINAL_PLAN" +%Y-%m-%dT%H:%M:%SZ
  )" \
  --arg approved_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg approval_reference "$FINAL_APPROVAL_REFERENCE" \
  '{
    schema_version: "1.0",
    action: "create",
    source_commit: $source_commit,
    input_digest: $input_digest,
    plan_digest: $plan_digest,
    plan_created_at: $plan_created_at,
    approved_at: $approved_at,
    approval_reference: $approval_reference
  }' >"$FINAL_APPROVAL"
chmod 0600 "$FINAL_APPROVAL"

.venv/bin/python - "$FINAL_APPROVAL" "$PLAN_APPROVAL_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

approval = json.loads(Path(sys.argv[1]).read_text())
schema = json.loads(Path(sys.argv[2]).read_text())
Draft202012Validator(
    schema,
    format_checker=FormatChecker(),
).validate(approval)
PY

sha256sum -c "$FINAL_PLAN_DIGEST"
test "$(jq -r '.source_commit' "$FINAL_APPROVAL")" = "$SOURCE_COMMIT"
test "$(jq -r '.input_digest' "$FINAL_APPROVAL")" = \
  "$(sha256sum "$FINAL_INPUT_MANIFEST" | awk '{print $1}')"
test "$(jq -r '.plan_digest' "$FINAL_APPROVAL")" = \
  "$(sha256sum "$FINAL_PLAN" | awk '{print $1}')"

terraform -chdir=terraform/bootstrap apply \
  -input=false \
  "$FINAL_PLAN"
```

Export final readiness and timing evidence:

```bash
tee_output "$BACKEND_EVIDENCE_DIR/backend-readiness.json" \
  terraform -chdir=terraform/bootstrap output -json backend_readiness

tee_output "$BACKEND_EVIDENCE_DIR/backend-readiness.json.sha256" \
  sha256sum "$BACKEND_EVIDENCE_DIR/backend-readiness.json"

jq -e '.status == "ready" and .failure_class == "none"' \
  "$BACKEND_EVIDENCE_DIR/backend-readiness.json"

export ROLE_PROPAGATION_DELAY_SECONDS="<separately-measured-seconds>"
export APPROVAL_WAIT_SECONDS="$(
  jq -s '
    map(
      ((.approved_at | fromdateiso8601) -
       (.plan_created_at | fromdateiso8601))
    ) |
    add
  ' \
    "$BOOTSTRAP_CREATE_APPROVAL" \
    "$PRELIMINARY_APPROVAL" \
    "$FINAL_APPROVAL"
)"
export BOOTSTRAP_COMPLETED_EPOCH="$(date +%s)"
export BOOTSTRAP_ELAPSED_SECONDS="$((
  BOOTSTRAP_COMPLETED_EPOCH -
  BOOTSTRAP_STARTED_EPOCH -
  ROLE_PROPAGATION_DELAY_SECONDS -
  APPROVAL_WAIT_SECONDS
))"
test "$APPROVAL_WAIT_SECONDS" -ge 0
test "$BOOTSTRAP_ELAPSED_SECONDS" -ge 0
test "$BOOTSTRAP_ELAPSED_SECONDS" -le 1200

tee_output "$BACKEND_EVIDENCE_DIR/bootstrap-timing.json" \
  jq -n \
    --arg started_at "$(
      jq -r '.started_at' "$RUN_EVIDENCE_DIR/run-metadata.json"
    )" \
    --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson bootstrap_elapsed_seconds "$BOOTSTRAP_ELAPSED_SECONDS" \
    --argjson role_propagation_delay_seconds "$ROLE_PROPAGATION_DELAY_SECONDS" \
    --argjson approval_wait_seconds "$APPROVAL_WAIT_SECONDS" \
    '{
      started_at: $started_at,
      completed_at: $completed_at,
      bootstrap_elapsed_seconds: $bootstrap_elapsed_seconds,
      role_propagation_delay_seconds: $role_propagation_delay_seconds,
      approval_wait_seconds: $approval_wait_seconds
    }'
```

Final readiness is valid for at most one hour and only for the recorded source, identity,
coordinates, and execution context.

## A8. Initialize the isolated dependent roots

Copy the tracked Entra-only partial configurations, edit only the approved account name and
environment prefix, and confirm the keys remain distinct:

```bash
cp terraform/backend.hcl.example terraform/backend.hcl
cp terraform/capacity-probe/backend.hcl.example \
  terraform/capacity-probe/backend.hcl

terraform -chdir=terraform init \
  -reconfigure \
  -input=false \
  -backend-config=backend.hcl

terraform -chdir=terraform/capacity-probe init \
  -reconfigure \
  -input=false \
  -backend-config=backend.hcl
```

Both roots must use Entra authentication and consume current final readiness evidence. Verify that
missing, malformed, older-than-one-hour, failed, wrong-commit, wrong-coordinate,
wrong-execution-context, and colliding-key fixtures all fail closed. Only the valid case may reach
resource planning.

## A9. Verify replacement-operator recovery

Add a second authorized operator to the approved Entra group. Start timing after that operator
refreshes Azure authentication; measure role-propagation delay separately.

Perform recovery after the bootstrap, main, and capacity-probe state blobs have each been created.
The main and capacity-probe roots may contain resources, but their protected inputs must still
describe the reviewed configuration. Use a fresh shell authenticated only as the replacement
operator. Do not distribute a storage key, SAS, copied token, or shared credential.

For the combined T057 run, execute A9 after B10 and before B11. Do not execute A9 before Part B:
initializing a backend does not by itself guarantee that its state blob exists.

Re-establish the protected paths and begin timing immediately after authentication:

```bash
umask 077

az login --tenant "<approved-tenant-id>"
az account set --subscription "<approved-subscription-id>"

export RECOVERY_AUTHENTICATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export RECOVERY_STARTED_EPOCH="$(date +%s)"
export SOURCE_COMMIT="$(git rev-parse HEAD)"
export RUN_ID="<original-run-id>"
export BACKEND_ENVIRONMENT="demo"
export BOOTSTRAP_STATE_ROOT="${BOOTSTRAP_STATE_ROOT:-/state/terraform-backend}"
export BOOTSTRAP_STATE_DIR="$BOOTSTRAP_STATE_ROOT/$BACKEND_ENVIRONMENT"
export BOOTSTRAP_TFVARS="$BOOTSTRAP_STATE_DIR/bootstrap.tfvars"
export FINAL_TFVARS="$BOOTSTRAP_STATE_DIR/readiness-final.tfvars.json"
export DEMO_STATE_DIR="${DEMO_STATE_DIR:-/state/slurm-bursting}"
export TFVARS_FILE="$PWD/terraform/environments/demo.tfvars"
export PROBE_TFVARS_FILE="$DEMO_STATE_DIR/probe.tfvars"
export RECOVERY_PLAN_DIR="$BOOTSTRAP_STATE_DIR/replacement-operator"
export RECOVERY_EVIDENCE_DIR="/evidence/quickstart/$RUN_ID/backend-bootstrap"
export BACKEND_EVIDENCE_DIR="$RECOVERY_EVIDENCE_DIR"
export RECOVERY_RESULTS="$RECOVERY_EVIDENCE_DIR/operator-recovery.json"

install -d -m 0700 "$RECOVERY_PLAN_DIR"
install -d -m 0700 "$RECOVERY_EVIDENCE_DIR"

test -f "$BOOTSTRAP_TFVARS"
test -f "$FINAL_TFVARS"
test -f "$TFVARS_FILE"
test -f "$PROBE_TFVARS_FILE"
test -f terraform/bootstrap/backend.azurerm.tf
test -f terraform/backend.hcl
test -f terraform/capacity-probe/backend.hcl
```

Capture the replacement identity without credentials and normalize the Azure CLI principal type to
the contract values:

```bash
export RECOVERY_TENANT_ID="$(az account show --query tenantId --output tsv)"
export RECOVERY_AZURE_PRINCIPAL_TYPE="$(
  az account show --query user.type --output tsv
)"
case "$RECOVERY_AZURE_PRINCIPAL_TYPE" in
  user)
    export RECOVERY_PRINCIPAL_TYPE="User"
    export RECOVERY_PRINCIPAL_ID="$(
      az ad signed-in-user show --query id --output tsv
    )"
    ;;
  servicePrincipal)
    export RECOVERY_PRINCIPAL_TYPE="ServicePrincipal"
    export RECOVERY_PRINCIPAL_ID="$(
      az ad sp show \
        --id "$(az account show --query user.name --output tsv)" \
        --query id \
        --output tsv
    )"
    ;;
  *)
    printf 'Unsupported Azure principal type: %s\n' \
      "$RECOVERY_AZURE_PRINCIPAL_TYPE" >&2
    false
    ;;
esac
```

If the principal type is unsupported, stop without running the next block:

```bash
test "$RECOVERY_TENANT_ID" = \
  "$(jq -r '.tenant_id' "$BACKEND_EVIDENCE_DIR/backend-coordinates.json")"
```

For service-principal authentication, replace the fallback principal lookup with the approved
service-principal object ID and verify it against the approval record. Do not record a client ID,
token, certificate, or secret in evidence.

Resolve the selected endpoint and prove Entra-authenticated Blob reachability:

```bash
export RECOVERY_STORAGE_ACCOUNT_NAME="$(
  jq -r '.storage_account_name' \
    "$BACKEND_EVIDENCE_DIR/backend-coordinates.json"
)"
export RECOVERY_CONTAINER_NAME="$(
  jq -r '.container_name' \
    "$BACKEND_EVIDENCE_DIR/backend-coordinates.json"
)"
export RECOVERY_BLOB_HOST="$RECOVERY_STORAGE_ACCOUNT_NAME.blob.core.windows.net"

getent ahostsv4 "$RECOVERY_BLOB_HOST" |
  awk '{print $1}' |
  sort -u |
  grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'

az storage container show \
  --auth-mode login \
  --account-name "$RECOVERY_STORAGE_ACCOUNT_NAME" \
  --name "$RECOVERY_CONTAINER_NAME" \
  --output none
```

Initialize each root and read each state directly:

```bash
terraform -chdir=terraform/bootstrap init \
  -reconfigure \
  -input=false
terraform -chdir=terraform init \
  -reconfigure \
  -input=false \
  -backend-config=backend.hcl
terraform -chdir=terraform/capacity-probe init \
  -reconfigure \
  -input=false \
  -backend-config=backend.hcl

terraform -chdir=terraform/bootstrap state pull \
  >"$RECOVERY_PLAN_DIR/bootstrap-state.json"
terraform -chdir=terraform state pull \
  >"$RECOVERY_PLAN_DIR/main-state.json"
terraform -chdir=terraform/capacity-probe state pull \
  >"$RECOVERY_PLAN_DIR/capacity-probe-state.json"
chmod 0600 "$RECOVERY_PLAN_DIR/"*-state.json

jq -e '.lineage | type == "string" and length > 0' \
  "$RECOVERY_PLAN_DIR/bootstrap-state.json" >/dev/null
jq -e '.lineage | type == "string" and length > 0' \
  "$RECOVERY_PLAN_DIR/main-state.json" >/dev/null
jq -e '.lineage | type == "string" and length > 0' \
  "$RECOVERY_PLAN_DIR/capacity-probe-state.json" >/dev/null
```

Successful no-refresh plans natively acquire and release each backend lock. Save all plans under
protected state, never apply them, and do not copy plans or raw logs into evidence:

```bash
set +e
terraform -chdir=terraform/bootstrap plan \
  -refresh=false \
  -detailed-exitcode \
  -input=false \
  -lock=true \
  -lock-timeout=0s \
  -var-file="$BOOTSTRAP_TFVARS" \
  -var-file="$FINAL_TFVARS" \
  -out="$RECOVERY_PLAN_DIR/bootstrap.tfplan"
BOOTSTRAP_RECOVERY_PLAN_STATUS="$?"

terraform -chdir=terraform plan \
  -refresh=false \
  -detailed-exitcode \
  -input=false \
  -lock=true \
  -lock-timeout=0s \
  -var-file="$TFVARS_FILE" \
  -out="$RECOVERY_PLAN_DIR/main.tfplan"
MAIN_RECOVERY_PLAN_STATUS="$?"

terraform -chdir=terraform/capacity-probe plan \
  -refresh=false \
  -detailed-exitcode \
  -input=false \
  -lock=true \
  -lock-timeout=0s \
  -var-file="$PROBE_TFVARS_FILE" \
  -out="$RECOVERY_PLAN_DIR/capacity-probe.tfplan"
PROBE_RECOVERY_PLAN_STATUS="$?"
set +e

test "$BOOTSTRAP_RECOVERY_PLAN_STATUS" -ne 1
test "$BOOTSTRAP_RECOVERY_PLAN_STATUS" -le 2
test "$MAIN_RECOVERY_PLAN_STATUS" -ne 1
test "$MAIN_RECOVERY_PLAN_STATUS" -le 2
test "$PROBE_RECOVERY_PLAN_STATUS" -ne 1
test "$PROBE_RECOVERY_PLAN_STATUS" -le 2
chmod 0600 "$RECOVERY_PLAN_DIR/"*.tfplan
```

Exit status zero means no changes and two means a plan with changes; both prove that Terraform
acquired the native lock, completed planning, and released the lock. Exit status one includes lock
acquisition or another planning failure and blocks recovery acceptance. Review but never apply
these recovery plans; their only acceptance purpose is native lock acquisition and release.

Finish the 15-minute measurement and write only bounded recovery results:

```bash
export RECOVERY_COMPLETED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export RECOVERY_COMPLETED_EPOCH="$(date +%s)"
export RECOVERY_ELAPSED_SECONDS="$((RECOVERY_COMPLETED_EPOCH - RECOVERY_STARTED_EPOCH))"
test "$RECOVERY_ELAPSED_SECONDS" -le 900

tee_output "$RECOVERY_RESULTS" \
  jq -n \
    --arg tenant_id "$RECOVERY_TENANT_ID" \
    --arg principal_id "$RECOVERY_PRINCIPAL_ID" \
    --arg principal_type "$RECOVERY_PRINCIPAL_TYPE" \
    --arg authenticated_at "$RECOVERY_AUTHENTICATED_AT" \
    --arg completed_at "$RECOVERY_COMPLETED_AT" \
    --argjson elapsed_seconds "$RECOVERY_ELAPSED_SECONDS" \
    '{
      replacement_operator: {
        tenant_id: $tenant_id,
        principal_id: $principal_id,
        principal_type: $principal_type,
        authenticated_at: $authenticated_at,
        completed_at: $completed_at,
        elapsed_seconds: $elapsed_seconds
      },
      namespace_access: {
        bootstrap: {
          initialized: true,
          read_succeeded: true,
          lock_succeeded: true
        },
        main: {
          initialized: true,
          read_succeeded: true,
          lock_succeeded: true
        },
        capacity_probe: {
          initialized: true,
          read_succeeded: true,
          lock_succeeded: true
        }
      }
    }'

jq -e \
  '.replacement_operator.elapsed_seconds <= 900 and
   ([
      .namespace_access[] |
      .initialized,
      .read_succeeded,
      .lock_succeeded
    ] | all)' \
  "$RECOVERY_RESULTS" >/dev/null
```

Record this file as the recovery-stage reference. A10 incorporates these exact bounded fields into
the final
[`backend-live-acceptance.schema.json`](../specs/003-terraform-backend-bootstrap/contracts/backend-live-acceptance.schema.json).

## A10. Validate managed removal

Existing mode has no unlock or backend-destroy operation.

For managed mode, first prove that main and capacity-probe state are readable and contain zero
managed resources. Destroy and verify those environments separately before backend removal.

Choose exactly one removal path:

- `acceptance`: bootstrap state was migrated to Azure Blob and MUST be reverse-migrated and
  verified before unlock. This path can satisfy FR-027 and live acceptance.
- `abandoned_pre_migration_cleanup`: authoritative bootstrap state never left the protected local
  backend. This recovery path is recorded separately and MUST NOT be reported as acceptance.

### A10.1 Re-establish protected paths

After a shell or terminal restart, restore these non-secret path variables. Use a new removal
evidence directory; never append cleanup results to the stopped run:

```bash
umask 077

export SOURCE_COMMIT="$(git rev-parse HEAD)"
export BACKEND_ENVIRONMENT="demo"
export BOOTSTRAP_STATE_ROOT="${BOOTSTRAP_STATE_ROOT:-/state/terraform-backend}"
export BOOTSTRAP_STATE_DIR="$BOOTSTRAP_STATE_ROOT/$BACKEND_ENVIRONMENT"
export BOOTSTRAP_TFVARS="$BOOTSTRAP_STATE_DIR/bootstrap.tfvars"
export BOOTSTRAP_LOCAL_STATE="$BOOTSTRAP_STATE_DIR/terraform.tfstate"
export REMOVAL_RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
export REMOVAL_EVIDENCE_DIR="/evidence/quickstart/$REMOVAL_RUN_ID/backend-bootstrap"
export LIFECYCLE_SCHEMA="$PWD/specs/003-terraform-backend-bootstrap/contracts/backend-lifecycle.schema.json"
export PLAN_APPROVAL_SCHEMA="$PWD/specs/003-terraform-backend-bootstrap/contracts/backend-plan-approval.schema.json"
export MANAGED_REMOVAL_SCHEMA="$PWD/specs/003-terraform-backend-bootstrap/contracts/backend-managed-removal.schema.json"
export LIVE_ACCEPTANCE_SCHEMA="$PWD/specs/003-terraform-backend-bootstrap/contracts/backend-live-acceptance.schema.json"

export REMOVAL_PATH="<acceptance-or-abandoned_pre_migration_cleanup>"
case "$REMOVAL_PATH" in
  acceptance)
    export STATE_MIGRATION_STATUS="reverse_migrated"
    export REVERSE_MIGRATION_VERIFIED="true"
    ;;
  abandoned_pre_migration_cleanup)
    export STATE_MIGRATION_STATUS="never_migrated"
    export REVERSE_MIGRATION_VERIFIED="false"
    ;;
  *)
    printf 'Unsupported removal path: %s\n' "$REMOVAL_PATH" >&2
    false
    ;;
esac
```

If the removal path is unsupported, stop without running the next block:

```bash
install -d -m 0700 "$REMOVAL_EVIDENCE_DIR"

test -f "$BOOTSTRAP_TFVARS"
test "$SOURCE_COMMIT" = "$(git rev-parse HEAD)"
```

If either prerequisite test fails, stop without running the backend initialization block:

```bash
if test "$REMOVAL_PATH" = "acceptance"; then
  test -f terraform/bootstrap/backend.azurerm.tf
  test ! -e terraform/bootstrap/backend.local.tf
else
  test -f "$BOOTSTRAP_LOCAL_STATE"
  test "$(stat -c '%a' "$BOOTSTRAP_LOCAL_STATE")" = "600"
  test -f terraform/bootstrap/backend.local.tf
  test ! -e terraform/bootstrap/backend.azurerm.tf

  terraform -chdir=terraform/bootstrap init \
    -reconfigure \
    -input=false \
    -backend-config="path=$BOOTSTRAP_LOCAL_STATE"
fi
```

The backend-file checks bind the selected path to its expected starting backend. They do not prove
state provenance if files were manually changed. Review migration evidence and state history before
continuing.

For `acceptance`, preserve the remote state before switching back to the local backend:

```bash
if test "$REMOVAL_PATH" = "acceptance"; then
  export REMOTE_STATE_BEFORE_REVERSE="$BOOTSTRAP_STATE_DIR/remote-state-before-reverse.json"
  export LOCAL_STATE_AFTER_REVERSE="$BOOTSTRAP_STATE_DIR/local-state-after-reverse.json"
  export REVERSE_LOCAL_MODE="failed"
  export REVERSE_LINEAGE_MATCHES="false"
  export REVERSE_RESOURCE_COUNT_MATCHES="false"
  export REVERSE_STABLE_STATE_MATCHES="false"

  terraform -chdir=terraform/bootstrap state pull \
    >"$REMOTE_STATE_BEFORE_REVERSE"
  chmod 0600 "$REMOTE_STATE_BEFORE_REVERSE"

  rm terraform/bootstrap/backend.azurerm.tf
  cp terraform/bootstrap/backend.local.tf.example \
    terraform/bootstrap/backend.local.tf

  terraform -chdir=terraform/bootstrap init \
    -migrate-state \
    -force-copy \
    -input=false \
    -backend-config="path=$BOOTSTRAP_LOCAL_STATE"

  terraform -chdir=terraform/bootstrap state pull \
    >"$LOCAL_STATE_AFTER_REVERSE"
  chmod 0600 "$LOCAL_STATE_AFTER_REVERSE" "$BOOTSTRAP_LOCAL_STATE"

  if test "$(stat -c '%a' "$BOOTSTRAP_LOCAL_STATE")" = "600"; then
    export REVERSE_LOCAL_MODE="0600"
  fi
  if test "$(jq -r '.lineage' "$LOCAL_STATE_AFTER_REVERSE")" = \
    "$(jq -r '.lineage' "$REMOTE_STATE_BEFORE_REVERSE")"; then
    export REVERSE_LINEAGE_MATCHES="true"
  fi
  if test "$(jq '[.resources[]?] | length' "$LOCAL_STATE_AFTER_REVERSE")" -eq \
    "$(jq '[.resources[]?] | length' "$REMOTE_STATE_BEFORE_REVERSE")"; then
    export REVERSE_RESOURCE_COUNT_MATCHES="true"
  fi
  if test "$(jq -S -c '{lineage, outputs, resources}' "$LOCAL_STATE_AFTER_REVERSE" | sha256sum | awk '{print $1}')" = \
    "$(jq -S -c '{lineage, outputs, resources}' "$REMOTE_STATE_BEFORE_REVERSE" | sha256sum | awk '{print $1}')"; then
    export REVERSE_STABLE_STATE_MATCHES="true"
  fi

  test "$REVERSE_LOCAL_MODE" = "0600"
  test "$REVERSE_LINEAGE_MATCHES" = "true"
  test "$REVERSE_RESOURCE_COUNT_MATCHES" = "true"
  test "$REVERSE_STABLE_STATE_MATCHES" = "true"
fi
```

Derive the non-secret resource coordinates from the authoritative local state:

```bash
export REMOVAL_COORDINATES_JSON="$(
  terraform -chdir=terraform/bootstrap output -json backend_coordinates
)"
export STORAGE_ACCOUNT_NAME="$(
  jq -er '.storage_account_name' <<<"$REMOVAL_COORDINATES_JSON"
)"
export STORAGE_ACCOUNT_RESOURCE_ID="$(
  jq -er '.resource_ids.storage_account' <<<"$REMOVAL_COORDINATES_JSON"
)"
export STATE_CONTAINER_NAME="$(
  jq -er '.container_name' <<<"$REMOVAL_COORDINATES_JSON"
)"
```

### A10.2 Prove dependent namespaces are absent

For a stopped pre-migration run, neither dependent namespace may have a state blob. Query only
existence; do not copy state content into evidence. For acceptance, both state blobs must exist and
their initialized roots must report zero managed resource instances:

```bash
export MAIN_STATE_KEY="$BACKEND_ENVIRONMENT/main.tfstate"
export PROBE_STATE_KEY="$BACKEND_ENVIRONMENT/capacity-probe.tfstate"

export MAIN_STATE_EXISTS="$(
  az storage blob exists \
    --auth-mode login \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --container-name "$STATE_CONTAINER_NAME" \
    --name "$MAIN_STATE_KEY" \
    --query exists \
    --output tsv
)"
export PROBE_STATE_EXISTS="$(
  az storage blob exists \
    --auth-mode login \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --container-name "$STATE_CONTAINER_NAME" \
    --name "$PROBE_STATE_KEY" \
    --query exists \
    --output tsv
)"

if test "$REMOVAL_PATH" = "abandoned_pre_migration_cleanup"; then
  export MAIN_STATE_STATUS="unreadable"
  export PROBE_STATE_STATUS="unreadable"
  test "$MAIN_STATE_EXISTS" = "false"
  test "$PROBE_STATE_EXISTS" = "false"

  if test "$MAIN_STATE_EXISTS" = "false" &&
    test "$PROBE_STATE_EXISTS" = "false"; then
    export MAIN_STATE_STATUS="absent"
    export MAIN_MANAGED_RESOURCE_COUNT="0"
    export PROBE_STATE_STATUS="absent"
    export PROBE_MANAGED_RESOURCE_COUNT="0"
  fi
else
  if test "$MAIN_STATE_EXISTS" = "true"; then
    terraform -chdir=terraform init \
      -reconfigure \
      -input=false \
      -backend-config=backend.hcl
    if MAIN_STATE_ADDRESSES="$(terraform -chdir=terraform state list)"; then
      export MAIN_MANAGED_RESOURCE_COUNT="$(
        awk 'NF {count++} END {print count + 0}' <<<"$MAIN_STATE_ADDRESSES"
      )"
      if test "$MAIN_MANAGED_RESOURCE_COUNT" -eq 0; then
        export MAIN_STATE_STATUS="empty"
      else
        export MAIN_STATE_STATUS="managed"
      fi
    else
      export MAIN_STATE_STATUS="unreadable"
      export MAIN_MANAGED_RESOURCE_COUNT="-1"
    fi
  else
    export MAIN_STATE_STATUS="absent"
    export MAIN_MANAGED_RESOURCE_COUNT="0"
  fi

  if test "$PROBE_STATE_EXISTS" = "true"; then
    terraform -chdir=terraform/capacity-probe init \
      -reconfigure \
      -input=false \
      -backend-config=backend.hcl
    if PROBE_STATE_ADDRESSES="$(
      terraform -chdir=terraform/capacity-probe state list
    )"; then
      export PROBE_MANAGED_RESOURCE_COUNT="$(
        awk 'NF {count++} END {print count + 0}' <<<"$PROBE_STATE_ADDRESSES"
      )"
      if test "$PROBE_MANAGED_RESOURCE_COUNT" -eq 0; then
        export PROBE_STATE_STATUS="empty"
      else
        export PROBE_STATE_STATUS="managed"
      fi
    else
      export PROBE_STATE_STATUS="unreadable"
      export PROBE_MANAGED_RESOURCE_COUNT="-1"
    fi
  else
    export PROBE_STATE_STATUS="absent"
    export PROBE_MANAGED_RESOURCE_COUNT="0"
  fi

  test "$MAIN_MANAGED_RESOURCE_COUNT" -eq 0
  test "$PROBE_MANAGED_RESOURCE_COUNT" -eq 0
fi
```

For abandoned cleanup, stop if either existence result is `true`. For acceptance, stop if either
resource count is nonzero or unreadable; an absent state is allowed only when that dependent root
was never created. Separately destroy and verify any nonempty dependent root before returning to
A10. Do not relabel an existing state blob as absent or an uninspected state as empty.

### A10.3 Bind the authoritative local state

Create a protected verification copy, compare semantic state identity, and bind subsequent plans to
the current local-state digest:

```bash
export REMOVAL_STATE_VERIFICATION="$BOOTSTRAP_STATE_DIR/removal-state-verification.json"

terraform -chdir=terraform/bootstrap state pull \
  >"$REMOVAL_STATE_VERIFICATION"
chmod 0600 "$REMOVAL_STATE_VERIFICATION"

test "$(jq -r '.lineage' "$REMOVAL_STATE_VERIFICATION")" = \
  "$(jq -r '.lineage' "$BOOTSTRAP_LOCAL_STATE")"
test "$(jq '[.resources[]?] | length' "$REMOVAL_STATE_VERIFICATION")" -eq \
  "$(jq '[.resources[]?] | length' "$BOOTSTRAP_LOCAL_STATE")"

export EXPECTED_LOCAL_STATE_DIGEST="$(
  sha256sum "$BOOTSTRAP_LOCAL_STATE" |
    awk '{print $1}'
)"
export OBSERVED_LOCAL_STATE_DIGEST="$(
  sha256sum "$BOOTSTRAP_LOCAL_STATE" |
    awk '{print $1}'
)"

test "$OBSERVED_LOCAL_STATE_DIGEST" = "$EXPECTED_LOCAL_STATE_DIGEST"
```

The two digest variables are intentionally captured at separate lifecycle boundaries below.
Recalculate `OBSERVED_LOCAL_STATE_DIGEST` immediately before each plan and require it to match
`EXPECTED_LOCAL_STATE_DIGEST`.

### A10.4 Generate and review the lock-only plan

Record an external review reference for unlock. The reference identifies the accountable review,
but approval of the exact digest occurs only after plan generation. Run the `read` command directly
in an interactive terminal, not through a noninteractive task runner:

```bash
read -r -p "Authorized unlock review reference: " \
  UNLOCK_APPROVAL_REFERENCE
test -n "$UNLOCK_APPROVAL_REFERENCE"
```

If the prompt returns EOF or the reference is empty, stop without running the next block:

```bash
export UNLOCK_TFVARS="$BOOTSTRAP_STATE_DIR/unlock.tfvars.json"
export UNLOCK_INPUT_MANIFEST="$BOOTSTRAP_STATE_DIR/unlock-inputs.json"
export UNLOCK_PLAN="$BOOTSTRAP_STATE_DIR/unlock.tfplan"
export UNLOCK_PLAN_DIGEST="$BOOTSTRAP_STATE_DIR/unlock.tfplan.sha256"
export UNLOCK_APPROVAL="$BOOTSTRAP_STATE_DIR/unlock-approval.json"
export UNLOCK_STALE_PLAN="$BOOTSTRAP_STATE_DIR/unlock-stale.tfplan"
export UNLOCK_STALE_LOG="$BOOTSTRAP_STATE_DIR/unlock-stale.log"

export OBSERVED_LOCAL_STATE_DIGEST="$(
  sha256sum "$BOOTSTRAP_LOCAL_STATE" |
    awk '{print $1}'
)"
test "$OBSERVED_LOCAL_STATE_DIGEST" = "$EXPECTED_LOCAL_STATE_DIGEST"

jq -n \
  --arg source_commit "$SOURCE_COMMIT" \
  --arg assessed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg approval_reference "$UNLOCK_APPROVAL_REFERENCE" \
  --arg main_state_status "$MAIN_STATE_STATUS" \
  --argjson main_count "$MAIN_MANAGED_RESOURCE_COUNT" \
  --arg probe_state_status "$PROBE_STATE_STATUS" \
  --argjson probe_count "$PROBE_MANAGED_RESOURCE_COUNT" \
  --arg state_digest "$OBSERVED_LOCAL_STATE_DIGEST" \
  --arg removal_path "$REMOVAL_PATH" \
  --arg state_migration_status "$STATE_MIGRATION_STATUS" \
  --argjson reverse_migration_verified "$REVERSE_MIGRATION_VERIFIED" \
  '{
    source_commit: $source_commit,
    lifecycle_action: "unlock",
    lifecycle_assertions: {
      assessed_at: $assessed_at,
      approval_reference: $approval_reference,
      main_state_status: $main_state_status,
      main_managed_resource_count: $main_count,
      probe_state_status: $probe_state_status,
      probe_managed_resource_count: $probe_count,
      bootstrap_state_location: "local",
      bootstrap_state_digest: $state_digest,
      expected_state_digest: $state_digest,
      removal_path: $removal_path,
      state_migration_status: $state_migration_status,
      reverse_migration_verified: $reverse_migration_verified
    }
  }' >"$UNLOCK_TFVARS"
chmod 0600 "$UNLOCK_TFVARS"

jq -n \
  --arg bootstrap_tfvars_sha256 "$(
    sha256sum "$BOOTSTRAP_TFVARS" |
      awk '{print $1}'
  )" \
  --arg lifecycle_tfvars_sha256 "$(
    sha256sum "$UNLOCK_TFVARS" |
      awk '{print $1}'
  )" \
  --arg local_state_sha256 "$OBSERVED_LOCAL_STATE_DIGEST" \
  '{
    bootstrap_tfvars_sha256: $bootstrap_tfvars_sha256,
    lifecycle_tfvars_sha256: $lifecycle_tfvars_sha256,
    local_state_sha256: $local_state_sha256
  }' >"$UNLOCK_INPUT_MANIFEST"
chmod 0600 "$UNLOCK_INPUT_MANIFEST"

terraform -chdir=terraform/bootstrap plan \
  -input=false \
  -var-file="$BOOTSTRAP_TFVARS" \
  -var-file="$UNLOCK_TFVARS" \
  -out="$UNLOCK_PLAN"

sha256sum "$UNLOCK_PLAN" >"$UNLOCK_PLAN_DIGEST"
chmod 0600 "$UNLOCK_PLAN" "$UNLOCK_PLAN_DIGEST"
cp --preserve=mode "$UNLOCK_PLAN" "$UNLOCK_STALE_PLAN"

terraform -chdir=terraform/bootstrap show -no-color "$UNLOCK_PLAN"
```

Mechanically require exactly one infrastructure change: deletion of the managed storage-account
lock. Output changes are permitted because source and lifecycle evidence are being updated:

```bash
export UNLOCK_CHANGE_SUMMARY="$(
  terraform -chdir=terraform/bootstrap show -json "$UNLOCK_PLAN" |
    jq -c '[
      .resource_changes[]? |
      select(.change.actions != ["no-op"]) |
      {
        address: .address,
        actions: .change.actions
      }
    ]'
)"

test "$(jq 'length' <<<"$UNLOCK_CHANGE_SUMMARY")" -eq 1
test "$(jq -r '.[0].address' <<<"$UNLOCK_CHANGE_SUMMARY")" = \
  'module.storage[0].azapi_resource.lock[0]'
test "$(jq -c '.[0].actions' <<<"$UNLOCK_CHANGE_SUMMARY")" = '["delete"]'
```

### A10.5 Approve and apply only the unlock plan

After an authorized reviewer approves the displayed plan, create the protected approval record:

```bash
export UNLOCK_PLAN_CREATED_AT="$(
  date -u -r "$UNLOCK_PLAN" +%Y-%m-%dT%H:%M:%SZ
)"
export UNLOCK_APPROVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export UNLOCK_INPUT_DIGEST="$(
  sha256sum "$UNLOCK_INPUT_MANIFEST" |
    awk '{print $1}'
)"

jq -n \
  --arg source_commit "$SOURCE_COMMIT" \
  --arg input_digest "$UNLOCK_INPUT_DIGEST" \
  --arg plan_digest "$(
    sha256sum "$UNLOCK_PLAN" |
      awk '{print $1}'
  )" \
  --arg plan_created_at "$UNLOCK_PLAN_CREATED_AT" \
  --arg approved_at "$UNLOCK_APPROVED_AT" \
  --arg approval_reference "$UNLOCK_APPROVAL_REFERENCE" \
  '{
    schema_version: "1.0",
    action: "unlock",
    source_commit: $source_commit,
    input_digest: $input_digest,
    plan_digest: $plan_digest,
    plan_created_at: $plan_created_at,
    approved_at: $approved_at,
    approval_reference: $approval_reference
  }' >"$UNLOCK_APPROVAL"
chmod 0600 "$UNLOCK_APPROVAL"

.venv/bin/python - \
  "$UNLOCK_APPROVAL" \
  "$PLAN_APPROVAL_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

approval = json.loads(Path(sys.argv[1]).read_text())
schema = json.loads(Path(sys.argv[2]).read_text())
Draft202012Validator(
    schema,
    format_checker=FormatChecker(),
).validate(approval)
PY

sha256sum -c "$UNLOCK_PLAN_DIGEST"
test "$(jq -r '.source_commit' "$UNLOCK_APPROVAL")" = "$SOURCE_COMMIT"
test "$(jq -r '.input_digest' "$UNLOCK_APPROVAL")" = \
  "$(sha256sum "$UNLOCK_INPUT_MANIFEST" | awk '{print $1}')"
test "$(jq -r '.plan_digest' "$UNLOCK_APPROVAL")" = \
  "$(sha256sum "$UNLOCK_PLAN" | awk '{print $1}')"
test "$(sha256sum "$BOOTSTRAP_LOCAL_STATE" | awk '{print $1}')" = \
  "$EXPECTED_LOCAL_STATE_DIGEST"

terraform -chdir=terraform/bootstrap apply \
  -input=false \
  "$UNLOCK_PLAN"
```

Export and validate the secret-free unlock classification, then prove the lock is absent:

```bash
export UNLOCK_LIFECYCLE_EVIDENCE="$REMOVAL_EVIDENCE_DIR/backend-lifecycle-unlock.json"

tee_output "$UNLOCK_LIFECYCLE_EVIDENCE" \
  terraform -chdir=terraform/bootstrap output -json backend_lifecycle

.venv/bin/python - \
  "$UNLOCK_LIFECYCLE_EVIDENCE" \
  "$LIFECYCLE_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

evidence = json.loads(Path(sys.argv[1]).read_text())
schema_path = Path(sys.argv[2])
schema = json.loads(schema_path.read_text())
registry = Registry()
for path in schema_path.parent.glob("*.schema.json"):
    referenced_schema = json.loads(path.read_text())
    registry = registry.with_resource(
        referenced_schema["$id"],
        Resource.from_contents(referenced_schema),
    )
Draft202012Validator(
    schema,
    registry=registry,
    format_checker=FormatChecker(),
).validate(evidence)
PY

test "$(jq -r '.status' "$UNLOCK_LIFECYCLE_EVIDENCE")" = "ready"
test "$(jq -r '.action' "$UNLOCK_LIFECYCLE_EVIDENCE")" = "unlock"
test "$(jq -r '.bootstrap_state.removal_path' "$UNLOCK_LIFECYCLE_EVIDENCE")" = \
  "$REMOVAL_PATH"
test "$(jq -r '.bootstrap_state.migration_status' "$UNLOCK_LIFECYCLE_EVIDENCE")" = \
  "$STATE_MIGRATION_STATUS"
test "$(jq -r '.bootstrap_state.reverse_migration_verified' "$UNLOCK_LIFECYCLE_EVIDENCE")" = \
  "$REVERSE_MIGRATION_VERIFIED"

test "$(
  az lock list \
    --resource-group "$(
      jq -er '.resource_group_name' <<<"$REMOVAL_COORDINATES_JSON"
    )" \
    --resource "$STORAGE_ACCOUNT_NAME" \
    --resource-type Microsoft.Storage/storageAccounts \
    --query "[?level == 'CanNotDelete'] | length(@)" \
    --output tsv
)" -eq 0
```

Prove Terraform rejects the now-stale saved copy. Keep the raw diagnostic under `/state`:

```bash
set +e
terraform -chdir=terraform/bootstrap apply \
  -input=false \
  "$UNLOCK_STALE_PLAN" >"$UNLOCK_STALE_LOG" 2>&1
UNLOCK_STALE_STATUS="$?"
set +e

test "$UNLOCK_STALE_STATUS" -ne 0
grep -Fq "Saved plan is stale" "$UNLOCK_STALE_LOG"
export UNLOCK_STALE_PLAN_REJECTED="true"
```

### A10.6 Generate a separate destroy plan

Create a new lifecycle input file and rebind the expected digest to the post-unlock local state.
The destroy approval must be a separate post-generation approval record with `action = "destroy"`.
It may use the same external change-ticket reference as unlock if that ticket separately records
both approval events. Run the `read` command directly in an interactive terminal:

```bash
read -r -p "Authorized destroy review reference: " \
  DESTROY_APPROVAL_REFERENCE
test -n "$DESTROY_APPROVAL_REFERENCE"
```

If the prompt returns EOF or the reference is empty, stop without running the next block:

```bash
export DESTROY_TFVARS="$BOOTSTRAP_STATE_DIR/destroy.tfvars.json"
export DESTROY_INPUT_MANIFEST="$BOOTSTRAP_STATE_DIR/destroy-inputs.json"
export DESTROY_PLAN="$BOOTSTRAP_STATE_DIR/destroy.tfplan"
export DESTROY_PLAN_DIGEST="$BOOTSTRAP_STATE_DIR/destroy.tfplan.sha256"
export DESTROY_APPROVAL="$BOOTSTRAP_STATE_DIR/destroy-approval.json"
export DESTROY_STALE_PLAN="$BOOTSTRAP_STATE_DIR/destroy-stale.tfplan"
export DESTROY_STALE_LOG="$BOOTSTRAP_STATE_DIR/destroy-stale.log"
export EXPECTED_LOCAL_STATE_DIGEST="$(
  sha256sum "$BOOTSTRAP_LOCAL_STATE" |
    awk '{print $1}'
)"

jq -n \
  --arg source_commit "$SOURCE_COMMIT" \
  --arg assessed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg approval_reference "$DESTROY_APPROVAL_REFERENCE" \
  --arg main_state_status "$MAIN_STATE_STATUS" \
  --argjson main_count "$MAIN_MANAGED_RESOURCE_COUNT" \
  --arg probe_state_status "$PROBE_STATE_STATUS" \
  --argjson probe_count "$PROBE_MANAGED_RESOURCE_COUNT" \
  --arg state_digest "$EXPECTED_LOCAL_STATE_DIGEST" \
  --arg removal_path "$REMOVAL_PATH" \
  --arg state_migration_status "$STATE_MIGRATION_STATUS" \
  --argjson reverse_migration_verified "$REVERSE_MIGRATION_VERIFIED" \
  '{
    source_commit: $source_commit,
    lifecycle_action: "destroy",
    lifecycle_assertions: {
      assessed_at: $assessed_at,
      approval_reference: $approval_reference,
      main_state_status: $main_state_status,
      main_managed_resource_count: $main_count,
      probe_state_status: $probe_state_status,
      probe_managed_resource_count: $probe_count,
      bootstrap_state_location: "local",
      bootstrap_state_digest: $state_digest,
      expected_state_digest: $state_digest,
      removal_path: $removal_path,
      state_migration_status: $state_migration_status,
      reverse_migration_verified: $reverse_migration_verified
    }
  }' >"$DESTROY_TFVARS"
chmod 0600 "$DESTROY_TFVARS"

jq -n \
  --arg bootstrap_tfvars_sha256 "$(
    sha256sum "$BOOTSTRAP_TFVARS" |
      awk '{print $1}'
  )" \
  --arg lifecycle_tfvars_sha256 "$(
    sha256sum "$DESTROY_TFVARS" |
      awk '{print $1}'
  )" \
  --arg local_state_sha256 "$EXPECTED_LOCAL_STATE_DIGEST" \
  '{
    bootstrap_tfvars_sha256: $bootstrap_tfvars_sha256,
    lifecycle_tfvars_sha256: $lifecycle_tfvars_sha256,
    local_state_sha256: $local_state_sha256
  }' >"$DESTROY_INPUT_MANIFEST"
chmod 0600 "$DESTROY_INPUT_MANIFEST"

terraform -chdir=terraform/bootstrap plan \
  -destroy \
  -input=false \
  -var-file="$BOOTSTRAP_TFVARS" \
  -var-file="$DESTROY_TFVARS" \
  -out="$DESTROY_PLAN"

sha256sum "$DESTROY_PLAN" >"$DESTROY_PLAN_DIGEST"
chmod 0600 "$DESTROY_PLAN" "$DESTROY_PLAN_DIGEST"
cp --preserve=mode "$DESTROY_PLAN" "$DESTROY_STALE_PLAN"

terraform -chdir=terraform/bootstrap show -no-color "$DESTROY_PLAN"
```

Reject an empty destroy plan, any create/update/replacement action, or any attempt to recreate the
lock:

```bash
export DESTROY_CHANGE_SUMMARY="$(
  terraform -chdir=terraform/bootstrap show -json "$DESTROY_PLAN" |
    jq -c '[
      .resource_changes[]? |
      select(.change.actions != ["no-op"]) |
      {
        address: .address,
        actions: .change.actions
      }
    ]'
)"

test "$(jq 'length' <<<"$DESTROY_CHANGE_SUMMARY")" -gt 0
jq -e 'all(.[]; .actions == ["delete"])' \
  <<<"$DESTROY_CHANGE_SUMMARY" >/dev/null
jq -e 'all(.[];
  .address != "module.storage[0].azapi_resource.lock[0]"
)' <<<"$DESTROY_CHANGE_SUMMARY" >/dev/null
```

Evaluate the native destroy lifecycle classification before apply removes outputs:

```bash
export DESTROY_LIFECYCLE_EVIDENCE="$REMOVAL_EVIDENCE_DIR/backend-lifecycle-destroy.json"

set +e
printf 'jsonencode(local.backend_lifecycle)\n' |
  terraform -chdir=terraform/bootstrap console \
    -var-file="$BOOTSTRAP_TFVARS" \
    -var-file="$DESTROY_TFVARS" |
  jq -r 'fromjson' |
  tee "$DESTROY_LIFECYCLE_EVIDENCE"
DESTROY_PIPE_STATUSES=("${PIPESTATUS[@]}")
set +e

test "${DESTROY_PIPE_STATUSES[0]}" -eq 0
test "${DESTROY_PIPE_STATUSES[1]}" -eq 0
test "${DESTROY_PIPE_STATUSES[2]}" -eq 0
test "${DESTROY_PIPE_STATUSES[3]}" -eq 0

.venv/bin/python - \
  "$DESTROY_LIFECYCLE_EVIDENCE" \
  "$LIFECYCLE_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

evidence = json.loads(Path(sys.argv[1]).read_text())
schema_path = Path(sys.argv[2])
schema = json.loads(schema_path.read_text())
registry = Registry()
for path in schema_path.parent.glob("*.schema.json"):
    referenced_schema = json.loads(path.read_text())
    registry = registry.with_resource(
        referenced_schema["$id"],
        Resource.from_contents(referenced_schema),
    )
Draft202012Validator(
    schema,
    registry=registry,
    format_checker=FormatChecker(),
).validate(evidence)
PY

test "$(jq -r '.status' "$DESTROY_LIFECYCLE_EVIDENCE")" = "ready"
test "$(jq -r '.action' "$DESTROY_LIFECYCLE_EVIDENCE")" = "destroy"
```

### A10.7 Approve and apply only the destroy plan

Create a distinct post-generation approval:

```bash
export DESTROY_PLAN_CREATED_AT="$(
  date -u -r "$DESTROY_PLAN" +%Y-%m-%dT%H:%M:%SZ
)"
export DESTROY_APPROVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
export DESTROY_INPUT_DIGEST="$(
  sha256sum "$DESTROY_INPUT_MANIFEST" |
    awk '{print $1}'
)"

jq -n \
  --arg source_commit "$SOURCE_COMMIT" \
  --arg input_digest "$DESTROY_INPUT_DIGEST" \
  --arg plan_digest "$(
    sha256sum "$DESTROY_PLAN" |
      awk '{print $1}'
  )" \
  --arg plan_created_at "$DESTROY_PLAN_CREATED_AT" \
  --arg approved_at "$DESTROY_APPROVED_AT" \
  --arg approval_reference "$DESTROY_APPROVAL_REFERENCE" \
  '{
    schema_version: "1.0",
    action: "destroy",
    source_commit: $source_commit,
    input_digest: $input_digest,
    plan_digest: $plan_digest,
    plan_created_at: $plan_created_at,
    approved_at: $approved_at,
    approval_reference: $approval_reference
  }' >"$DESTROY_APPROVAL"
chmod 0600 "$DESTROY_APPROVAL"

.venv/bin/python - \
  "$DESTROY_APPROVAL" \
  "$PLAN_APPROVAL_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

approval = json.loads(Path(sys.argv[1]).read_text())
schema = json.loads(Path(sys.argv[2]).read_text())
Draft202012Validator(
    schema,
    format_checker=FormatChecker(),
).validate(approval)
PY

sha256sum -c "$DESTROY_PLAN_DIGEST"
test "$(jq -r '.source_commit' "$DESTROY_APPROVAL")" = "$SOURCE_COMMIT"
test "$(jq -r '.input_digest' "$DESTROY_APPROVAL")" = \
  "$(sha256sum "$DESTROY_INPUT_MANIFEST" | awk '{print $1}')"
test "$(jq -r '.plan_digest' "$DESTROY_APPROVAL")" = \
  "$(sha256sum "$DESTROY_PLAN" | awk '{print $1}')"
test "$(sha256sum "$BOOTSTRAP_LOCAL_STATE" | awk '{print $1}')" = \
  "$EXPECTED_LOCAL_STATE_DIGEST"

terraform -chdir=terraform/bootstrap apply \
  -input=false \
  "$DESTROY_PLAN"
```

Prove the saved duplicate is stale:

```bash
set +e
terraform -chdir=terraform/bootstrap apply \
  -input=false \
  "$DESTROY_STALE_PLAN" >"$DESTROY_STALE_LOG" 2>&1
DESTROY_STALE_STATUS="$?"
set +e

test "$DESTROY_STALE_STATUS" -ne 0
grep -Fq "Saved plan is stale" "$DESTROY_STALE_LOG"
export DESTROY_STALE_PLAN_REJECTED="true"
```

### A10.8 Verify absence and record bounded removal evidence

Verify through Azure Resource Manager that no storage account exists at the exact recorded resource
ID. A container cannot exist after its parent account is absent:

```bash
export STORAGE_ACCOUNT_RESOURCE_COUNT="$(
  az resource list \
    --resource-type Microsoft.Storage/storageAccounts \
    --query '[].id' \
    --output json |
    jq \
      --arg resource_id "$STORAGE_ACCOUNT_RESOURCE_ID" \
      '[
        .[] |
        select(
          ascii_downcase ==
          ($resource_id | ascii_downcase)
        )
      ] | length'
)"

test "$STORAGE_ACCOUNT_RESOURCE_COUNT" -eq 0

export ACCOUNT_ABSENT="true"
export CONTAINER_ABSENT="true"
```

Record only bounded digests, references, stale-plan results, and absence Booleans matching
[`backend-managed-removal.schema.json`](../specs/003-terraform-backend-bootstrap/contracts/backend-managed-removal.schema.json):

```bash
if test "$REMOVAL_PATH" = "abandoned_pre_migration_cleanup"; then
tee_output "$REMOVAL_EVIDENCE_DIR/managed-removal.json" \
  jq -n \
    --arg source_commit "$SOURCE_COMMIT" \
    --arg removal_run_id "$REMOVAL_RUN_ID" \
    --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg unlock_plan_digest "$(
      sha256sum "$UNLOCK_PLAN" |
        awk '{print $1}'
    )" \
    --arg unlock_reference "$UNLOCK_APPROVAL_REFERENCE" \
    --argjson unlock_stale "$UNLOCK_STALE_PLAN_REJECTED" \
    --arg destroy_plan_digest "$(
      sha256sum "$DESTROY_PLAN" |
        awk '{print $1}'
    )" \
    --arg destroy_reference "$DESTROY_APPROVAL_REFERENCE" \
    --argjson destroy_stale "$DESTROY_STALE_PLAN_REJECTED" \
    --argjson account_absent "$ACCOUNT_ABSENT" \
    --argjson container_absent "$CONTAINER_ABSENT" \
    '{
      schema_version: "1.0",
      source_commit: $source_commit,
      removal_run_id: $removal_run_id,
      completed_at: $completed_at,
      removal_path: "abandoned_pre_migration_cleanup",
      state_migration_status: "never_migrated",
      reverse_migration_verified: false,
      dependent_namespaces: {
        main: {
          status: "absent",
          managed_resource_count: 0
        },
        capacity_probe: {
          status: "absent",
          managed_resource_count: 0
        }
      },
      unlock: {
        plan_sha256: $unlock_plan_digest,
        approval_reference: $unlock_reference,
        stale_plan_rejected: $unlock_stale,
        applied_plan_digest_matches: true
      },
      destroy: {
        plan_sha256: $destroy_plan_digest,
        approval_reference: $destroy_reference,
        stale_plan_rejected: $destroy_stale,
        applied_plan_digest_matches: true
      },
      backend_absence: {
        account_absent: $account_absent,
        container_absent: $container_absent
      },
      status: "passed"
    }'

tee_output "$REMOVAL_EVIDENCE_DIR/managed-removal.json.sha256" \
  sha256sum "$REMOVAL_EVIDENCE_DIR/managed-removal.json"

.venv/bin/python - \
  "$REMOVAL_EVIDENCE_DIR/managed-removal.json" \
  "$MANAGED_REMOVAL_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

evidence = json.loads(Path(sys.argv[1]).read_text())
schema = json.loads(Path(sys.argv[2]).read_text())
Draft202012Validator(
    schema,
    format_checker=FormatChecker(),
).validate(evidence)
PY

sha256sum -c \
  "$REMOVAL_EVIDENCE_DIR/managed-removal.json.sha256"
fi
```

For acceptance, verify secret hygiene and assemble the complete live-acceptance record. Restore the
original run ID; do not substitute the cleanup-only removal run ID:

```bash
if test "$REMOVAL_PATH" = "acceptance"; then
  export ACCEPTANCE_RUN_ID="<original-run-id>"
  export LIVE_ACCEPTANCE_STATUS="<passed-or-failed>"
  case "$LIVE_ACCEPTANCE_STATUS" in
    passed|failed) ;;
    *)
      printf 'LIVE_ACCEPTANCE_STATUS must be passed or failed.\n' >&2
      LIVE_ACCEPTANCE_STATUS="failed"
      ;;
  esac
  export ACCEPTANCE_EVIDENCE_ROOT="/evidence/quickstart/$ACCEPTANCE_RUN_ID"
  export ACCEPTANCE_BACKEND_EVIDENCE="$ACCEPTANCE_EVIDENCE_ROOT/backend-bootstrap"
  export RECOVERY_RESULTS="$ACCEPTANCE_BACKEND_EVIDENCE/operator-recovery.json"
  export BOOTSTRAP_TIMING="$ACCEPTANCE_BACKEND_EVIDENCE/bootstrap-timing.json"
  export LIVE_ACCEPTANCE_EVIDENCE="$REMOVAL_EVIDENCE_DIR/backend-live-acceptance.json"
  export GIT_SECRET_SCAN_LOG="$BOOTSTRAP_STATE_DIR/git-secret-scan.log"
  export EVIDENCE_SECRET_SCAN_LOG="$BOOTSTRAP_STATE_DIR/evidence-secret-scan.log"

  test -f "$RECOVERY_RESULTS"
  test -f "$BOOTSTRAP_TIMING"
  test "$REVERSE_LOCAL_MODE" = "0600"
  test "$REVERSE_LINEAGE_MATCHES" = "true"
  test "$REVERSE_RESOURCE_COUNT_MATCHES" = "true"
  test "$REVERSE_STABLE_STATE_MATCHES" = "true"

  set +e
  git grep -I -n -E \
    '(-----BEGIN [A-Z ]*PRIVATE K[E]Y-----|Account[K]ey=|SharedAccess[S]ignature=|[?&]s[i]g=)' \
    >"$GIT_SECRET_SCAN_LOG"
  GIT_SECRET_SCAN_STATUS="$?"
  grep -R -I -n -E \
    '("(account_key|access_token|client_secret|password|sas_token)"[[:space:]]*:|-----BEGIN [A-Z ]*PRIVATE KEY-----|AccountKey=|SharedAccessSignature=|[?&]sig=)' \
    "$ACCEPTANCE_EVIDENCE_ROOT" >"$EVIDENCE_SECRET_SCAN_LOG"
  EVIDENCE_SECRET_SCAN_STATUS="$?"
  set +e

  test "$GIT_SECRET_SCAN_STATUS" -eq 1
  test "$EVIDENCE_SECRET_SCAN_STATUS" -eq 1
  test ! -s "$GIT_SECRET_SCAN_LOG"
  test ! -s "$EVIDENCE_SECRET_SCAN_LOG"

  export PROHIBITED_ARTIFACT_COUNT="$(
    find "$ACCEPTANCE_EVIDENCE_ROOT" -type f \
      \( -name '*.tfstate' -o -name '*.tfplan' -o -name '*.tfvars' \
         -o -name '*.pem' -o -name '*.key' \) |
      wc -l
  )"
  test "$PROHIBITED_ARTIFACT_COUNT" -eq 0

  test -f "$ACCEPTANCE_EVIDENCE_ROOT/run-metadata.json"
  test -f "$ACCEPTANCE_BACKEND_EVIDENCE/backend-coordinates.json"
  test -f "$ACCEPTANCE_BACKEND_EVIDENCE/backend-readiness-preliminary.json"
  test -f "$ACCEPTANCE_BACKEND_EVIDENCE/backend-migration-acceptance.json"
  test -f "$ACCEPTANCE_BACKEND_EVIDENCE/backend-readiness.json"
  test -f "$RECOVERY_RESULTS"
  test -f "$UNLOCK_LIFECYCLE_EVIDENCE"
  test -f "$DESTROY_LIFECYCLE_EVIDENCE"
  export DEPENDENT_STAGE_REFERENCE="$ACCEPTANCE_EVIDENCE_ROOT/slurm-demo/main-cleanup.json"
  export PROBE_CLEANUP_REFERENCE="$ACCEPTANCE_EVIDENCE_ROOT/slurm-demo/capacity-probe/capacity-probe.json"
  test -f "$DEPENDENT_STAGE_REFERENCE"
  test -f "$PROBE_CLEANUP_REFERENCE"
  jq -e \
    '.status == "passed" and
     .main.managed_resource_count == 0 and
     .capacity_probe.managed_resource_count == 0 and
     .capacity_probe.cleanup_verified' \
    "$DEPENDENT_STAGE_REFERENCE" >/dev/null
  jq -e \
    '.allocation_state == "allocated" and .cleanup_state == "verified"' \
    "$PROBE_CLEANUP_REFERENCE" >/dev/null

  LIVE_ACCEPTANCE_GATES_PASSED="false"
  if test -f "$RECOVERY_RESULTS" &&
    test -f "$BOOTSTRAP_TIMING" &&
    test "$REVERSE_LOCAL_MODE" = "0600" &&
    test "$REVERSE_LINEAGE_MATCHES" = "true" &&
    test "$REVERSE_RESOURCE_COUNT_MATCHES" = "true" &&
    test "$REVERSE_STABLE_STATE_MATCHES" = "true" &&
    test "$GIT_SECRET_SCAN_STATUS" -eq 1 &&
    test "$EVIDENCE_SECRET_SCAN_STATUS" -eq 1 &&
    test "$PROHIBITED_ARTIFACT_COUNT" -eq 0 &&
    test -f "$DEPENDENT_STAGE_REFERENCE" &&
    test -f "$PROBE_CLEANUP_REFERENCE" &&
    jq -e \
      '.status == "passed" and
       .main.managed_resource_count == 0 and
       .capacity_probe.managed_resource_count == 0 and
       .capacity_probe.cleanup_verified' \
      "$DEPENDENT_STAGE_REFERENCE" >/dev/null &&
    jq -e \
      '.allocation_state == "allocated" and .cleanup_state == "verified"' \
      "$PROBE_CLEANUP_REFERENCE" >/dev/null; then
    LIVE_ACCEPTANCE_GATES_PASSED="true"
  fi

  if test "$LIVE_ACCEPTANCE_GATES_PASSED" = "true"; then
    tee_output "$LIVE_ACCEPTANCE_EVIDENCE" \
    jq -n \
      --arg source_commit "$SOURCE_COMMIT" \
      --arg run_id "$ACCEPTANCE_RUN_ID" \
      --arg acceptance_status "$LIVE_ACCEPTANCE_STATUS" \
      --slurpfile timing "$BOOTSTRAP_TIMING" \
      --slurpfile recovery "$RECOVERY_RESULTS" \
      --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg local_mode "$REVERSE_LOCAL_MODE" \
      --argjson lineage_matches "$REVERSE_LINEAGE_MATCHES" \
      --argjson resource_count_matches "$REVERSE_RESOURCE_COUNT_MATCHES" \
      --argjson stable_state_matches "$REVERSE_STABLE_STATE_MATCHES" \
      --arg unlock_plan_digest "$(sha256sum "$UNLOCK_PLAN" | awk '{print $1}')" \
      --arg unlock_reference "$UNLOCK_APPROVAL_REFERENCE" \
      --argjson unlock_stale "$UNLOCK_STALE_PLAN_REJECTED" \
      --arg destroy_plan_digest "$(sha256sum "$DESTROY_PLAN" | awk '{print $1}')" \
      --arg destroy_reference "$DESTROY_APPROVAL_REFERENCE" \
      --argjson destroy_stale "$DESTROY_STALE_PLAN_REJECTED" \
      --argjson account_absent "$ACCOUNT_ABSENT" \
      --argjson container_absent "$CONTAINER_ABSENT" \
      --argjson prohibited_artifact_count "$PROHIBITED_ARTIFACT_COUNT" \
      --arg bootstrap_reference "$ACCEPTANCE_BACKEND_EVIDENCE/backend-coordinates.json" \
      --arg preliminary_reference "$ACCEPTANCE_BACKEND_EVIDENCE/backend-readiness-preliminary.json" \
      --arg migration_reference "$ACCEPTANCE_BACKEND_EVIDENCE/backend-migration-acceptance.json" \
      --arg dependent_reference "$DEPENDENT_STAGE_REFERENCE" \
      --arg recovery_reference "$RECOVERY_RESULTS" \
      --arg unlock_reference_file "$UNLOCK_LIFECYCLE_EVIDENCE" \
      --arg removal_reference "$DESTROY_LIFECYCLE_EVIDENCE" \
      '{
        schema_version: "1.0",
        source_commit: $source_commit,
        run_id: $run_id,
        started_at: $timing[0].started_at,
        completed_at: $completed_at,
        bootstrap_elapsed_seconds: $timing[0].bootstrap_elapsed_seconds,
        role_propagation_delay_seconds: $timing[0].role_propagation_delay_seconds,
        approval_wait_seconds: $timing[0].approval_wait_seconds,
        replacement_operator: $recovery[0].replacement_operator,
        namespace_access: $recovery[0].namespace_access,
        reverse_migration: {
          local_mode: $local_mode,
          lineage_matches: $lineage_matches,
          resource_count_matches: $resource_count_matches,
          stable_state_matches: $stable_state_matches
        },
        unlock: {
          plan_digest: $unlock_plan_digest,
          approval_reference: $unlock_reference,
          stale_plan_rejected: $unlock_stale,
          applied_digest_matches: true
        },
        destroy: {
          plan_digest: $destroy_plan_digest,
          approval_reference: $destroy_reference,
          stale_plan_rejected: $destroy_stale,
          applied_digest_matches: true
        },
        backend_absence: {
          account_absent: $account_absent,
          container_absent: $container_absent
        },
        secret_hygiene: {
          git_scan_passed: true,
          evidence_scan_passed: true,
          prohibited_artifact_count: $prohibited_artifact_count
        },
        stages: {
          bootstrap: {recorded: true, reference: $bootstrap_reference},
          preliminary_readiness: {recorded: true, reference: $preliminary_reference},
          migration_final_readiness: {recorded: true, reference: $migration_reference},
          dependent_initialization_deployment: {recorded: true, reference: $dependent_reference},
          recovery: {recorded: true, reference: $recovery_reference},
          unlock: {recorded: true, reference: $unlock_reference_file},
          removal: {recorded: true, reference: $removal_reference},
          undocumented_command_count: 0,
          workflow_substitution_count: 0
        },
        status: $acceptance_status
      }'

    tee_output "$LIVE_ACCEPTANCE_EVIDENCE.sha256" \
      sha256sum "$LIVE_ACCEPTANCE_EVIDENCE"

    .venv/bin/python - "$LIVE_ACCEPTANCE_EVIDENCE" "$LIVE_ACCEPTANCE_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

evidence = json.loads(Path(sys.argv[1]).read_text())
schema = json.loads(Path(sys.argv[2]).read_text())
Draft202012Validator(
    schema,
    format_checker=FormatChecker(),
).validate(evidence)
PY

    sha256sum -c "$LIVE_ACCEPTANCE_EVIDENCE.sha256"
  else
    printf 'Live-acceptance gates failed; no success-shaped evidence was written.\n' >&2
  fi
  test "$LIVE_ACCEPTANCE_GATES_PASSED" = "true"
fi
```

Do not delete the protected local state, plans, approvals, manifests, or raw stale-plan logs until
the bounded removal evidence has been reviewed and retained according to policy.

Any non-empty dependent state, unverified state provenance, wrong local-state mode, state-digest
mismatch, unexpected plan action, stale plan accepted, mismatched approval, or ambiguous Azure
absence result blocks removal.

Record bootstrap, preliminary readiness, migration/final readiness, dependent initialization and
deployment, recovery, unlock, and removal as separate stages. Acceptance requires zero
undocumented commands and zero workflow substitutions.

## A11. Retain the managed backend for Part B

This section is an execution-order handoff, not an alternative bootstrap implementation. Use it
only for a combined backend and Slurm acceptance run.

1. Complete A1 through A7 to create the managed account, validate preliminary readiness, migrate
   bootstrap state to Azure Blob, prove remote state and locking, and export current final
   readiness.
2. Complete A8 to initialize the main and capacity-probe roots with their exact distinct keys.
3. Do **not** execute A9 or A10 yet. Keep the storage account, container, deletion lock, role
   assignments, and all three state namespaces available.
4. Continue through B10 using the same `RUN_ID`, `SOURCE_COMMIT`, final readiness evidence, backend
   coordinates, and execution context.
5. Execute A9 while bootstrap, main, and capacity-probe state blobs remain available.
6. Execute B11 to remove the main deployment and verify both dependent states are empty.
7. After B11 passes, return to A10. For a completed combined run, reverse-migrate bootstrap state
   and use
   `state_migration_status = "reverse_migrated"` with
   `reverse_migration_verified = true`.

Immediately before Part B, require the retained handoff:

```bash
test "$(jq -r '.status' \
  "$BACKEND_EVIDENCE_DIR/backend-readiness.json")" = "ready"
test "$(jq -r '.failure_class' \
  "$BACKEND_EVIDENCE_DIR/backend-readiness.json")" = "none"
test "$(jq -r '.source_commit' \
  "$BACKEND_EVIDENCE_DIR/backend-readiness.json")" = "$SOURCE_COMMIT"

test -f terraform/backend.hcl
test -f terraform/capacity-probe/backend.hcl

test "$(awk -F= '/^[[:space:]]*key[[:space:]]*=/{gsub(/[ "\t]/, "", $2); print $2}' \
  terraform/backend.hcl)" = "$BACKEND_ENVIRONMENT/main.tfstate"
test "$(awk -F= '/^[[:space:]]*key[[:space:]]*=/{gsub(/[ "\t]/, "", $2); print $2}' \
  terraform/capacity-probe/backend.hcl)" = \
  "$BACKEND_ENVIRONMENT/capacity-probe.tfstate"

test "$(
  az resource list \
    --resource-type Microsoft.Storage/storageAccounts \
    --query '[].id' \
    --output json |
    jq \
      --arg resource_id "$STORAGE_ACCOUNT_RESOURCE_ID" \
      '[
        .[] |
        select(
          ascii_downcase ==
          ($resource_id | ascii_downcase)
        )
      ] | length'
)" -eq 1
```

Final readiness is valid for at most one hour. If it expires before a Part B plan, repeat the direct
readiness observations and apply a newly reviewed final output-only readiness plan; never edit the
old evidence timestamp.

---

# Part B: Slurm bursting demo

Part B assumes the combined-run path in A11 retained the managed backend, produced current final
readiness, and initialized the main and capacity-probe roots. After B10, execute A9, then return to
B11 for cleanup. Return to A10 only after B11 passes.

## B1. Prepare the protected demo inputs

```bash
export TFVARS_FILE="$PWD/terraform/environments/demo.tfvars"

cp terraform/environments/demo.tfvars.example "$TFVARS_FILE"
chmod 0600 "$TFVARS_FILE"
git check-ignore -v "$TFVARS_FILE"

persist_run_context
```

Edit the file with approved:

- subscription, tenant, and existing Entra security-group object IDs;
- the governed backend environment prefix, which may differ from the workload naming prefix;
- distinct source and burst regions;
- one explicit burst zone and ordered approved alternate placements;
- private CIDRs;
- exact role counts and VM SKUs;
- independent exact scheduler and burst-compute image URNs from the same AlmaLinux family and
  major release;
- pinned CycleCloud `8.9.3` and Windows image;
- the approved runner's exact IPv4 `/32`, with
  `key_vault_provisioning_access_enabled = true` only for initial secret creation;
- an accountable review reference that explicitly authorizes `SecurityControl=Ignore` on only the
  Key Vault during that bounded provisioning window;
- versioned Key Vault references and other protected inputs.

Do not copy the `.tfvars` file into `/evidence`.

Generate all local credentials only in protected run state. Do not add them to `.tfvars`, ordinary
logs, or evidence:

```bash
export CYCLECLOUD_SSH_PRIVATE_KEY_FILE="$DEMO_STATE_DIR/cyclecloud-admin"
export CYCLECLOUD_SSH_PUBLIC_KEY_FILE="${CYCLECLOUD_SSH_PRIVATE_KEY_FILE}.pub"
export SCHEDULER_SSH_PRIVATE_KEY_FILE="$DEMO_STATE_DIR/scheduler-admin"
export SCHEDULER_SSH_PUBLIC_KEY_FILE="${SCHEDULER_SSH_PRIVATE_KEY_FILE}.pub"
export WINDOWS_ADMIN_PASSWORD_FILE="$DEMO_STATE_DIR/windows-admin-password"

if test ! -f "$CYCLECLOUD_SSH_PRIVATE_KEY_FILE"; then
  ssh-keygen -t rsa -b 4096 -m PEM -N '' \
    -f "$CYCLECLOUD_SSH_PRIVATE_KEY_FILE"
fi
if test ! -f "$SCHEDULER_SSH_PRIVATE_KEY_FILE"; then
  ssh-keygen -t rsa -b 4096 -m PEM -N '' \
    -f "$SCHEDULER_SSH_PRIVATE_KEY_FILE"
fi
if test ! -f "$WINDOWS_ADMIN_PASSWORD_FILE"; then
  printf 'Aa1!%s' "$(openssl rand -base64 36)" \
    >"$WINDOWS_ADMIN_PASSWORD_FILE"
fi
chmod 0600 \
  "$CYCLECLOUD_SSH_PRIVATE_KEY_FILE" \
  "$SCHEDULER_SSH_PRIVATE_KEY_FILE" \
  "$WINDOWS_ADMIN_PASSWORD_FILE"
chmod 0644 \
  "$CYCLECLOUD_SSH_PUBLIC_KEY_FILE" \
  "$SCHEDULER_SSH_PUBLIC_KEY_FILE"

export TF_VAR_scheduler_admin_ssh_public_key="$(
  tr -d '\r\n' <"$SCHEDULER_SSH_PUBLIC_KEY_FILE"
)"
export TF_VAR_windows_admin_password="$(
  tr -d '\r\n' <"$WINDOWS_ADMIN_PASSWORD_FILE"
)"
```

Re-export these two sensitive Terraform variables from the protected files after any shell resume.
Do not add them to `persist_run_context`.

## B2. Export and review preflight values

Derive values from the protected `.tfvars`; do not manually duplicate them:

```bash
source tests/end-to-end/export_preflight_env.sh "$TFVARS_FILE"
```

Review the shell-safe values printed by the helper. Confirm the active Azure subscription matches
`TARGET_SUBSCRIPTION_ID`.

Inspect Marketplace terms and legal links:

```bash
tee_output "$DEMO_EVIDENCE_DIR/marketplace-terms.json" \
  tests/end-to-end/marketplace_terms.sh show "$TFVARS_FILE"
```

If the terms are not already accepted, an authorized operator must review the links and
deliberately run:

```bash
ACCEPT_MARKETPLACE_TERMS=yes \
  tests/end-to-end/marketplace_terms.sh accept "$TFVARS_FILE"
```

Export and render static preflight evidence:

```bash
export PREFLIGHT_RESULTS_FILE="$DEMO_EVIDENCE_DIR/preflight.json"

persist_run_context

if tee_output "$PREFLIGHT_RESULTS_FILE" \
  tests/end-to-end/preflight.sh; then
  PREFLIGHT_STATUS=0
  tee_output "$DEMO_EVIDENCE_DIR/preflight-summary.md" \
    tests/end-to-end/render_preflight_summary.sh \
      "$PREFLIGHT_RESULTS_FILE"
  PREFLIGHT_SUMMARY_STATUS="$?"
else
  PREFLIGHT_STATUS="$?"
  PREFLIGHT_SUMMARY_STATUS=1
  printf 'Preflight failed with exit status %s; summary generation was skipped.\n' \
    "$PREFLIGHT_STATUS" >&2
fi

test "$PREFLIGHT_STATUS" -eq 0
test "$PREFLIGHT_SUMMARY_STATUS" -eq 0
```

Review the Markdown summary in VS Code, but treat the JSON as authoritative. Confirm:

- exact SKU and image eligibility in each role's region;
- image-family and major-release compatibility;
- source and burst regions are distinct;
- selected burst zone restrictions;
- required, current, limit, available, and projected remaining vCPUs for total regional and
  applicable VM-family quota;
- all ordered alternate placement assessments; and
- zero blockers.

An alternate assessment is advisory. To select it, edit the protected inputs and restart static
preflight, capacity probe, main plan review, and approval. Never carry forward evidence from the
previous placement.

## B3. Run the isolated capacity probe

Set protected operational paths:

```bash
export PROBE_TFVARS_FILE="$DEMO_STATE_DIR/probe.tfvars"
export PROBE_PLAN_FILE="$DEMO_STATE_DIR/capacity-probe.tfplan"
export PROBE_APPROVAL_FILE="$DEMO_STATE_DIR/capacity-probe-approval.json"
export PROBE_DESTROY_PLAN_FILE="$DEMO_STATE_DIR/capacity-probe-destroy.tfplan"
export PROBE_CLEANUP_APPROVAL_FILE="$DEMO_STATE_DIR/capacity-probe-destroy-approval.json"
export PROBE_EVIDENCE_DIR="$DEMO_EVIDENCE_DIR/capacity-probe"

install -d -m 0700 "$PROBE_EVIDENCE_DIR"

cp terraform/capacity-probe/probe.tfvars.example "$PROBE_TFVARS_FILE"
chmod 0600 "$PROBE_TFVARS_FILE"

persist_run_context
```

Edit `$PROBE_TFVARS_FILE` with the exact selected subscription, tenant, workload environment,
governed backend environment, burst region, zone, SKU, image, current backend-readiness file,
source commit, active principal, execution-context digest, an expiration no more than 24 hours
ahead, accountable owner, and `cost_acknowledged = true`. The workload `environment_name` and
backend `backend_environment_name` must independently match the protected demo inputs; do not
substitute one for the other.

Explicitly acknowledge temporary Azure cost in each approval record. Then:

```bash
tests/end-to-end/capacity_probe.sh plan
```

Review the exact saved plan, calculate the already emitted digest, and create
`$PROBE_APPROVAL_FILE` with:

```json
{
  "plan_digest": "<exact probe plan SHA-256>",
  "cost_acknowledged": true
}
```

Apply only that reviewed plan:

```bash
if tests/end-to-end/capacity_probe.sh apply; then
  PROBE_APPLY_STATUS=0
else
  PROBE_APPLY_STATUS="$?"
  printf 'Capacity-probe apply failed with exit status %s; acceptance stops, but continue only with the reviewed cleanup path.\n' \
    "$PROBE_APPLY_STATUS" >&2
fi
test "$PROBE_APPLY_STATUS" -eq 0
```

Require one exact burst node to allocate within 15 minutes. Generate the cleanup plan, capturing
failure without terminating the operator shell:

```bash
if tests/end-to-end/capacity_probe.sh cleanup-plan; then
  PROBE_CLEANUP_PLAN_STATUS=0
else
  PROBE_CLEANUP_PLAN_STATUS="$?"
  printf 'Capacity-probe cleanup planning failed with exit status %s.\n' \
    "$PROBE_CLEANUP_PLAN_STATUS" >&2
fi
test "$PROBE_CLEANUP_PLAN_STATUS" -eq 0
```

Review the exact destroy plan and digest. Only afterward, create its separate protected approval:

```bash
terraform -chdir=terraform/capacity-probe show -no-color \
  "$PROBE_DESTROY_PLAN_FILE"

if read -r -p "Authorized capacity-probe cleanup reference: " \
  PROBE_CLEANUP_APPROVAL_REFERENCE &&
  test -n "$PROBE_CLEANUP_APPROVAL_REFERENCE"; then
  jq -n \
    --arg plan_digest "$(
      sha256sum "$PROBE_DESTROY_PLAN_FILE" | awk '{print $1}'
    )" \
    --arg approval_reference "$PROBE_CLEANUP_APPROVAL_REFERENCE" \
    '{
      plan_digest: $plan_digest,
      cost_acknowledged: true,
      approval_reference: $approval_reference
    }' >"$PROBE_CLEANUP_APPROVAL_FILE"
  chmod 0600 "$PROBE_CLEANUP_APPROVAL_FILE"
else
  printf 'No capacity-probe cleanup approval was recorded; stop.\n' >&2
fi
test -f "$PROBE_CLEANUP_APPROVAL_FILE"
```

Apply only the approved cleanup plan and verify the bounded result:

```bash
if tests/end-to-end/capacity_probe.sh cleanup; then
  PROBE_CLEANUP_STATUS=0
else
  PROBE_CLEANUP_STATUS="$?"
  printf 'Capacity-probe cleanup failed with exit status %s; retain logs and stop.\n' \
    "$PROBE_CLEANUP_STATUS" >&2
fi

if test "$PROBE_CLEANUP_STATUS" -eq 0; then
  jq -e \
    '.allocation_state == "allocated" and .cleanup_state == "verified"' \
    "$PROBE_EVIDENCE_DIR/capacity-probe.json"
fi
test "$PROBE_CLEANUP_STATUS" -eq 0
```

Stop if allocation or cleanup fails. Probe success is point-in-time evidence, not a future or
multi-node capacity guarantee. The probe intentionally uses the exact pinned AlmaLinux HPC burst
image, SKU, region, and zone. It validates burst allocation independently of the CycleCloud
Marketplace appliance and does not need to reproduce the appliance image or its Bicep boundary.

## B4. Create and review the main saved plan

Use protected state for the saved plan and approval:

```bash
export PLAN_FILE="$DEMO_STATE_DIR/main.tfplan"
export APPROVAL_FILE="$DEMO_STATE_DIR/main-plan-approval.json"
export CAPACITY_PROBE_RESULTS_FILE="$PROBE_EVIDENCE_DIR/capacity-probe.json"

export TF_VAR_backend_readiness_file="$BACKEND_EVIDENCE_DIR/backend-readiness.json"
export TF_VAR_current_execution_context_digest="$(
  jq -er '.execution_context.runner_context_digest' \
    "$TF_VAR_backend_readiness_file"
)"
export TF_VAR_deployment_source_commit="$SOURCE_COMMIT"
export TF_VAR_deployment_principal_id="$(
  jq -er '.identity.principal_id' "$TF_VAR_backend_readiness_file"
)"
export TF_VAR_backend_storage_account_name="$(
  jq -er '.coordinates.storage_account_name' \
    "$TF_VAR_backend_readiness_file"
)"
export TF_VAR_backend_container_name="$(
  jq -er '.coordinates.container_name' "$TF_VAR_backend_readiness_file"
)"

persist_run_context

if terraform -chdir=terraform validate &&
  terraform -chdir=terraform plan \
    -input=false \
    -var-file="$TFVARS_FILE" \
    -out="$PLAN_FILE"; then
  MAIN_PLAN_STATUS=0
  tee_output "$DEMO_STATE_DIR/main.tfplan.sha256" \
    sha256sum "$PLAN_FILE"
  terraform -chdir=terraform show -no-color "$PLAN_FILE"
else
  MAIN_PLAN_STATUS="$?"
  printf 'Main planning failed with exit status %s; no approval may be created.\n' \
    "$MAIN_PLAN_STATUS" >&2
fi
test "$MAIN_PLAN_STATUS" -eq 0
```

Review interactively and confirm:

- only pinned providers and direct pinned AVM calls appear;
- no direct Azure resource or local custom Terraform module appears;
- the CycleCloud resource in this plan is a standalone Terraform-owned NIC, not a VM;
- Key Vault permits only the approved runner's exact `/32` for initial secret creation;
- exactly two VNETs and bidirectional global peerings are planned;
- exactly two Terraform-owned persistent VMs, one CycleCloud NIC, and one Bastion host are planned;
- scheduler and burst-compute roles use their independently pinned images;
- source/burst regions and burst zone match preflight and probe evidence;
- no unintended replacement or destruction appears; and
- sensitive values are redacted.

Create `$APPROVAL_FILE` only after plan generation:

```json
{
  "plan_digest": "<main plan SHA-256>",
  "preflight_digest": "<preflight.json SHA-256>",
  "capacity_probe_digest": "<capacity-probe.json SHA-256>",
  "approval_reference": "<approved change or review reference>",
  "key_vault_policy_exclusion_approved": true,
  "key_vault_provisioning_ipv4_cidr": "<approved runner IPv4>/32"
}
```

Any source, input, backend context, selected placement, plan, or evidence change invalidates
approval. Before apply, `provision.sh` also inspects the reviewed plan and requires exactly one
Key Vault create with public access enabled, default deny, exactly the approved runner `/32`, and
the Key Vault-only `SecurityControl=Ignore` tag. A stale private-only input therefore fails before
Azure resources are created. Final backend readiness must also be `ready/none` and no more than
20 minutes old when the foundation apply begins, preserving headroom for the immediate
post-foundation no-change plan.

## B5. Apply the exact reviewed Terraform foundation plan

`provision.sh` consumes the existing plan and never regenerates it:

```bash
export EVIDENCE_DIR="$DEMO_EVIDENCE_DIR"

if tests/end-to-end/provision.sh; then
  MAIN_APPLY_STATUS=0
else
  MAIN_APPLY_STATUS="$?"
  printf 'Main apply failed with exit status %s; retain protected logs and stop.\n' \
    "$MAIN_APPLY_STATUS" >&2
fi
test "$MAIN_APPLY_STATUS" -eq 0
```

The script verifies all three approved digests, rejects stale preflight evidence, applies only
`$PLAN_FILE`, and enforces the 90-minute target. It then generates an immediate verification plan
with detailed exit codes. Only status `0` is accepted; status `2` or a planning error blocks all
secret writes and CycleCloud deployment. The raw log remains beside the protected plan under
`/state`; evidence receives only `foundation-no-change.json`, including the result and raw-log
digest. This catches service normalization such as public-IP tag drift before the run expands.
At this point the Terraform foundation exists, but provisioning is not accepted: the CycleCloud VM
is absent and Key Vault still has the temporary runner `/32` and Key Vault-only policy-exclusion
tag.

Before writing secrets, use the reviewed foundation plan to prove the live exception is exactly
bounded. A recovered soft-deleted vault can retain its previous private-only network posture even
when the foundation apply requested the provisioning `/32`; never treat foundation-apply success
as proof of live Key Vault reachability:

```bash
export FOUNDATION_PLAN_FILE="$PLAN_FILE"
export KEY_VAULT_RECONCILIATION_PLAN_FILE="$DEMO_STATE_DIR/key-vault-reconciliation.tfplan"
export KEY_VAULT_RECONCILIATION_APPROVAL_FILE="$DEMO_STATE_DIR/key-vault-reconciliation-approval.json"
export KEY_VAULT_PROVISIONING_EVIDENCE_FILE="$DEMO_EVIDENCE_DIR/key-vault-provisioning-window.json"
persist_run_context

if tests/end-to-end/key_vault_reconciliation.sh check; then
  KEY_VAULT_POSTURE_STATUS=0
else
  KEY_VAULT_POSTURE_STATUS="$?"
fi
```

Status `0` proves the live posture matches the exact foundation plan and secret writing may
continue. Status `20` means soft-delete recovery retained another network posture. Any other status
is an error. For status `20`, generate a new plan; do not retry secret writes or alter the vault
through Azure CLI:

```bash
test "$KEY_VAULT_POSTURE_STATUS" -eq 20
tests/end-to-end/key_vault_reconciliation.sh plan
sha256sum "$KEY_VAULT_RECONCILIATION_PLAN_FILE"
terraform -chdir=terraform show -no-color "$KEY_VAULT_RECONCILIATION_PLAN_FILE"
```

The command rejects the plan unless its sole infrastructure action is an in-place update of the
AVM-managed Key Vault to the exact approved public-access, default-deny, `/32`, and Key Vault-only
policy-exclusion posture. After an authorized reviewer approves the displayed digest, create the
protected approval:

```bash
if read -r -p "Authorized Key Vault recovery-reconciliation reference: " \
  KEY_VAULT_RECONCILIATION_APPROVAL_REFERENCE &&
  test -n "$KEY_VAULT_RECONCILIATION_APPROVAL_REFERENCE"; then
  jq -n \
    --arg plan_digest "$(
      sha256sum "$KEY_VAULT_RECONCILIATION_PLAN_FILE" | awk '{print $1}'
    )" \
    --arg approval_reference "$KEY_VAULT_RECONCILIATION_APPROVAL_REFERENCE" \
    '{
      plan_digest: $plan_digest,
      approval_reference: $approval_reference,
      key_vault_policy_exclusion_approved: true
    }' >"$KEY_VAULT_RECONCILIATION_APPROVAL_FILE"
  chmod 0600 "$KEY_VAULT_RECONCILIATION_APPROVAL_FILE"
fi

test -f "$KEY_VAULT_RECONCILIATION_APPROVAL_FILE"
tests/end-to-end/key_vault_reconciliation.sh apply
```

The apply command revalidates the plan shape and digest, applies only that saved plan, and repeats
the live posture proof. Secret writing remains blocked unless the final evidence status is
`matched`, the exact `/32` is present, `SecurityControl=Ignore` exists only on the vault, and the
resource group remains untagged.

Write the protected credentials through the Key Vault data plane during this bounded window. The
script passes file paths rather than values to Azure CLI and records only secret IDs and names:

```bash
export ADMIN_SECRET_EVIDENCE_FILE="$DEMO_EVIDENCE_DIR/admin-secret-references.json"
tests/end-to-end/store_admin_secrets.sh
```

## B5.1. Review and deploy the CycleCloud VM-only stack

Set the protected artifacts:

```bash
export CYCLECLOUD_TEMPLATE_FILE="$DEMO_STATE_DIR/cyclecloud.json"
export CYCLECLOUD_PARAMETERS_FILE="$DEMO_STATE_DIR/cyclecloud.parameters.json"
export CYCLECLOUD_WHAT_IF_FILE="$DEMO_STATE_DIR/cyclecloud.what-if.json"
export CYCLECLOUD_APPROVAL_FILE="$DEMO_STATE_DIR/cyclecloud-approval.json"
export CYCLECLOUD_CLEANUP_PLAN_FILE="$DEMO_STATE_DIR/cyclecloud-cleanup-stack.json"
export CYCLECLOUD_CLEANUP_APPROVAL_FILE="$DEMO_STATE_DIR/cyclecloud-cleanup-approval.json"
export CYCLECLOUD_EVIDENCE_DIR="$DEMO_EVIDENCE_DIR/cyclecloud-stack"
install -d -m 0700 "$CYCLECLOUD_EVIDENCE_DIR"
persist_run_context
```

Compile the source-controlled Bicep template into the protected run, derive parameters from
Terraform outputs, validate them, and capture the exact what-if:

```bash
tests/end-to-end/cyclecloud_stack.sh prepare
tests/end-to-end/cyclecloud_stack.sh what-if
```

Review the compiled template and what-if. Azure can emit `Ignore` records for unrelated existing
resource-group resources; retain those records in the digest-bound raw what-if, but exclude them
from the VM-only actionable-change guard. Require every non-`Ignore` record to target the
`Microsoft.Compute/virtualMachines` resource named for CycleCloud, and require the initial
deployment to contain its create action. Confirm the matching pinned Marketplace plan and image,
the Terraform-owned NIC ID, no public IP, system identity, OS disk, and the required `FromImage`
data disk at LUN 0. Then create the approval:

```bash
if read -r -p "Authorized CycleCloud stack reference: " CYCLECLOUD_APPROVAL_REFERENCE &&
  test -n "$CYCLECLOUD_APPROVAL_REFERENCE"; then
  jq -n \
    --arg template_digest "$(sha256sum "$CYCLECLOUD_TEMPLATE_FILE" | awk '{print $1}')" \
    --arg parameters_digest "$(sha256sum "$CYCLECLOUD_PARAMETERS_FILE" | awk '{print $1}')" \
    --arg what_if_digest "$(sha256sum "$CYCLECLOUD_WHAT_IF_FILE" | awk '{print $1}')" \
    --arg approval_reference "$CYCLECLOUD_APPROVAL_REFERENCE" \
    '{
      template_digest: $template_digest,
      parameters_digest: $parameters_digest,
      what_if_digest: $what_if_digest,
      approval_reference: $approval_reference
    }' >"$CYCLECLOUD_APPROVAL_FILE"
  chmod 0600 "$CYCLECLOUD_APPROVAL_FILE"
fi
test -f "$CYCLECLOUD_APPROVAL_FILE"
tests/end-to-end/cyclecloud_stack.sh apply
```

Never reuse the approval after a template, parameter, source, state, or what-if change. A later
reconciliation runs `cyclecloud_stack.sh reconcile` and requires a new approval if any change is
reported.

## B5.2. Harden Key Vault to private-only access

Only after the one-time protected secret writes have succeeded, edit the protected demo inputs:

```hcl
key_vault_provisioning_access_enabled = false
key_vault_provisioning_ipv4_cidrs     = []
```

Create a new saved plan:

```bash
export HARDENING_PLAN_FILE="$DEMO_STATE_DIR/key-vault-hardening.tfplan"
export HARDENING_APPROVAL_FILE="$DEMO_STATE_DIR/key-vault-hardening-approval.json"

terraform -chdir=terraform plan \
  -input=false \
  -var-file="$TFVARS_FILE" \
  -out="$HARDENING_PLAN_FILE"
sha256sum "$HARDENING_PLAN_FILE"
terraform -chdir=terraform show -no-color "$HARDENING_PLAN_FILE"
```

Require only in-place Key Vault changes and prove the plan removes the policy exclusion. No
resource-group or other resource may change:

```bash
terraform -chdir=terraform show -json "$HARDENING_PLAN_FILE" |
  jq -e '
    [.resource_changes[] |
      select(.change.actions != ["no-op"])] as $changes |
    ($changes | length) > 0 and
    all($changes[];
      (.address | startswith("module.key_vault.")) and
      .change.actions == ["update"]
    ) and
    any($changes[];
      .change.before.tags.SecurityControl == "Ignore" and
      (.change.after.tags | has("SecurityControl") | not)
    )
  '
```

Record a digest-bound approval:

```bash
if read -r -p "Authorized Key Vault hardening reference: " HARDENING_APPROVAL_REFERENCE &&
  test -n "$HARDENING_APPROVAL_REFERENCE"; then
  jq -n \
    --arg plan_digest "$(sha256sum "$HARDENING_PLAN_FILE" | awk '{print $1}')" \
    --arg approval_reference "$HARDENING_APPROVAL_REFERENCE" \
    '{plan_digest: $plan_digest, approval_reference: $approval_reference}' \
    >"$HARDENING_APPROVAL_FILE"
  chmod 0600 "$HARDENING_APPROVAL_FILE"
fi

test "$(
  jq -er '.plan_digest' "$HARDENING_APPROVAL_FILE"
)" = "$(
  sha256sum "$HARDENING_PLAN_FILE" | awk '{print $1}'
)"
terraform -chdir=terraform apply -input=false "$HARDENING_PLAN_FILE"
```

Verify the accepted private-only posture before continuing:

```bash
KEY_VAULT_NAME="$(
  terraform -chdir=terraform output -json inventory |
    jq -er '.key_vault_private_name | split(".")[0]'
)"
RESOURCE_GROUP_NAME="$(
  terraform -chdir=terraform output -json cyclecloud_deployment |
    jq -er '.resource_group_name'
)"
az keyvault show \
  --resource-group "$RESOURCE_GROUP_NAME" \
  --name "$KEY_VAULT_NAME" \
  --query '{
    publicNetworkAccess:properties.publicNetworkAccess,
    defaultAction:properties.networkAcls.defaultAction,
    ipRules:properties.networkAcls.ipRules,
    securityControl:tags.SecurityControl
  }' --output json |
  tee "$DEMO_EVIDENCE_DIR/key-vault-hardening.json"
jq -e '
  .publicNetworkAccess == "Disabled" and
  .defaultAction == "Deny" and
  (.ipRules | length) == 0 and
  .securityControl == null
' "$DEMO_EVIDENCE_DIR/key-vault-hardening.json"

EVIDENCE_DIR="$DEMO_EVIDENCE_DIR" \
  tests/end-to-end/finalize_provisioning.sh
```

Provisioning remains failed unless the CycleCloud stack deployment and Key Vault hardening both
pass.

After B5.1 and B5.2, the secret-free evidence set contains:

```text
$DEMO_EVIDENCE_DIR/inventory.json
$DEMO_EVIDENCE_DIR/provisioning.json
$DEMO_EVIDENCE_DIR/admin-secret-references.json
$DEMO_EVIDENCE_DIR/cyclecloud-stack/deployment-stack.json
$DEMO_EVIDENCE_DIR/cyclecloud-stack/virtual-machine.json
$DEMO_EVIDENCE_DIR/key-vault-hardening.json
```

Validate the secret-free inventory and private infrastructure. The infrastructure verifier checks
the Terraform-managed private DNS records through the Azure control plane because the development
runner is intentionally outside the private VNET DNS resolution path:

```bash
run_logged "$DEMO_EVIDENCE_DIR/20-inventory-validation.log" \
  python3 tests/end-to-end/verify_inventory.py \
  "$DEMO_EVIDENCE_DIR/inventory.json"

export INVENTORY_FILE="$DEMO_EVIDENCE_DIR/inventory.json"
run_logged "$DEMO_EVIDENCE_DIR/21-infrastructure-validation.log" \
  tests/end-to-end/verify_infrastructure.sh
```

Confirm active provisioning completes within 90 minutes excluding approval waits, VM and
application public-inbound probes fail, the expected CycleCloud and Key Vault private DNS records
exist, and the two regional NAT Gateways have the exact subnet associations required below.
Runtime private DNS resolution remains a B7 assertion performed from the Windows administration
VM inside the source VNET.

## B6. Converge CycleCloud and scheduler twice

Use Bastion RDP to reach the Windows administration jump host. From that host, use SSH over the
private network to run:

- `chef/bin/converge-cyclecloud.sh` twice on the CycleCloud VM; and
- `chef/bin/converge-scheduler.sh` twice on the scheduler.

The second run on each host must report zero updated resources. Confirm CycleCloud `8.9.3`, the
pinned Slurm project/version, role-specific images, services, identities, `/sched`, `/shared`, and
the headless-template contracts.

`/evidence` exists only in the development container. Capture logs to a protected temporary
directory on each VM. Do not copy them directly into `/evidence`; use the B8.1 Bastion transfer
procedure to stage, verify, and promote them into:

```text
$DEMO_EVIDENCE_DIR/cyclecloud-converge-1.log
$DEMO_EVIDENCE_DIR/cyclecloud-converge-2.log
$DEMO_EVIDENCE_DIR/scheduler-converge-1.log
$DEMO_EVIDENCE_DIR/scheduler-converge-2.log
```

Do not use `set -x`; the convergence path consumes protected references and credential material.

## B7. Verify private Windows administration

From the Azure portal, connect to the Windows administration VM through the Bastion Standard
browser RDP experience. Record the Bastion resource ID, Windows VM resource ID, connection time,
and successful session result without recording credentials. A timeout or inability to establish
the portal session is an acceptance blocker. Do not create a direct Bastion SSH tunnel to the
scheduler or CycleCloud VM. Run:

```powershell
.\tests\end-to-end\verify_private_administration.ps1 `
  -CycleCloudPrivateName "<private-cyclecloud-name>" `
  -ClusterName "<cluster-name>" `
  -EvidencePath "<protected-path>\private-administration.json"
```

Confirm:

- the private name resolves;
- the certificate matches that name and chains to the trusted issuer;
- no certificate warning appears;
- the authorized application identity can authenticate;
- the imported headless cluster is visible; and
- an untrusted public client cannot resolve or connect.
- the Windows, scheduler, and CycleCloud VM NICs have no public IP configurations;
- the source access and management subnets reference the source-region NAT Gateway; and
- the burst compute subnet references the distinct burst-region NAT Gateway.

Transfer the resulting secret-free JSON with the B8.1 Windows Bastion handoff. Stage it under
`$DEMO_STATE_DIR/incoming/windows-admin/` before promotion into `$DEMO_EVIDENCE_DIR`.

## B8. Run the one-node burst job

From the Windows jump host, SSH to the scheduler. On the scheduler, from the checked-out
repository, use a protected temporary evidence directory:

```bash
export DEMO_USERNAME="<demo-user>"
export PARTITION="<slurm-partition>"
export SOURCE_REGION="<source-region>"
export BURST_REGION="<burst-region>"
export IDLE_TIMEOUT_MINUTES="<idle-timeout>"
export DEMO_UID_GID="<numeric-demo-uid>"
export EVIDENCE_DIR="<protected-temporary-directory-on-scheduler>"

set +e
tests/end-to-end/run_burst_demo.sh 2>&1 |
  tee "$EVIDENCE_DIR/run-burst-demo.log"
BURST_PIPE_STATUSES=("${PIPESTATUS[@]}")

test "${BURST_PIPE_STATUSES[0]}" -eq 0
test "${BURST_PIPE_STATUSES[1]}" -eq 0
```

Require, within 15 minutes under normal regional capacity:

1. the job moves from queued to configuring/running;
2. one CycleCloud compute node appears;
3. the job completes on that node;
4. output under the shared home identifies the execution node in the configured burst region
   while the scheduler remains in the source region; and
5. the node disappears after the configured idle timeout while scheduler health remains good.

Transfer the resulting evidence with the B8.1 scheduler tunnel into
`$DEMO_STATE_DIR/incoming/scheduler/` before promotion into
`$DEMO_EVIDENCE_DIR/burst-job/`.

## B8.1 Transfer node evidence through the Windows jump host

The Standard Bastion permits RDP only to the Windows administration VM. Bastion MUST NOT provide a
direct SSH or SCP tunnel to either Linux host. Portal/browser RDP is the required administration
acceptance path. For the protected evidence handoff, use an approved native RDP client with
protected-drive redirection, then use SSH and SCP from the Windows jump host to the private Linux
addresses. Session recording is disabled; the archive manifest, protected transfer logs, host-key
record, and promoted files are the transfer audit evidence. Do not use the Terraform `tfstate` container
as an evidence-transfer channel.

On each Linux VM, create a protected archive and manifest from the expected evidence directory.
Exclude the archive and manifest themselves:

```bash
export REMOTE_EVIDENCE_DIR="<protected-temporary-directory-on-vm>"
export REMOTE_ARCHIVE="/tmp/${HOSTNAME}-evidence.tar.gz"
export REMOTE_FILE_LIST="/tmp/${HOSTNAME}-evidence-files"

cd "$REMOTE_EVIDENCE_DIR"
find . -type f \
  ! -name MANIFEST.sha256 \
  -print0 |
  sort -z |
  xargs -0 sha256sum >MANIFEST.sha256
chmod 0600 MANIFEST.sha256
{
  printf 'MANIFEST.sha256\0'
  find . -type f ! -name MANIFEST.sha256 -printf '%P\0'
} >"$REMOTE_FILE_LIST"
chmod 0600 "$REMOTE_FILE_LIST"
tar --null --files-from="$REMOTE_FILE_LIST" -czf "$REMOTE_ARCHIVE"
chmod 0600 "$REMOTE_ARCHIVE"
```

On the development container, create the protected incoming layout:

```bash
export INCOMING_ROOT="$DEMO_STATE_DIR/incoming"
install -d -m 0700 \
  "$INCOMING_ROOT/cyclecloud" \
  "$INCOMING_ROOT/scheduler" \
  "$INCOMING_ROOT/windows-admin"
```

Open a native-client Bastion RDP session pinned to the validated Windows VM resource ID and redirect
only the protected incoming drive. On Windows, derive the scheduler and CycleCloud private
addresses from the validated inventory, record each SSH host key in protected Windows state, and
use the approved role-specific private key to pull each archive:

```powershell
$HostRole = "<cyclecloud-or-scheduler>"
$PrivateAddress = "<validated-private-address>"
$SshUsername = "<approved-linux-admin-user>"
$PrivateKey = "<protected-private-key-path>"
$KnownHosts = "<protected-windows-state-path>\known-hosts"
$RemoteArchive = "<remote-archive-path>"
$WindowsStaging = "<protected-windows-state-path>\$HostRole-evidence.tar.gz"

ssh-keyscan $PrivateAddress | Out-File -Append -Encoding ascii $KnownHosts
scp -i $PrivateKey `
  -o "UserKnownHostsFile=$KnownHosts" `
  "${SshUsername}@${PrivateAddress}:$RemoteArchive" `
  $WindowsStaging
```

Copy each archive from protected Windows staging to the matching role directory on the redirected
protected drive. Copy `private-administration.json` and its SHA-256 file into the redirected
`windows-admin` directory in the same RDP session. Do not enable a public VM endpoint, direct
Bastion SSH, WinRM, clipboard transfer, or an additional guest listener solely for evidence
transfer.

The two NAT Gateways are a self-contained demonstration choice, not a production landing-zone
recommendation. A production deployment should normally use governed hub/connectivity egress and
duplicate regional egress infrastructure only when a documented requirement makes it necessary.

Back in the development container, reject unsafe archive paths, extract into each role-specific
protected directory, verify every manifest digest, and require the secret-pattern scan to find no
matches:

```bash
export INCOMING_ROLE_DIR="$INCOMING_ROOT/$HOST_ROLE"

if tar -tzf "$INCOMING_ROLE_DIR/evidence.tar.gz" |
  grep -Eq '(^/|(^|/)\.\.(/|$))'; then
  printf 'Unsafe evidence archive path detected.\n' >&2
  false
fi

tar -xzf "$INCOMING_ROLE_DIR/evidence.tar.gz" \
  -C "$INCOMING_ROLE_DIR"

(
  cd "$INCOMING_ROLE_DIR"
  sha256sum -c MANIFEST.sha256
)

set +e
grep -R -I -n -E \
  '("(account_key|access_token|client_secret|password|sas_token)"[[:space:]]*:|-----BEGIN [A-Z ]*PRIVATE KEY-----|AccountKey=|SharedAccessSignature=|[?&]sig=)' \
  "$INCOMING_ROLE_DIR" \
  >"$DEMO_STATE_DIR/$HOST_ROLE-incoming-secret-scan.log"
INCOMING_SECRET_SCAN_STATUS="$?"
set +e

test "$INCOMING_SECRET_SCAN_STATUS" -eq 1
test ! -s "$DEMO_STATE_DIR/$HOST_ROLE-incoming-secret-scan.log"
```

Verify the Windows JSON digest and scan it with the same protected staging gates above.

After all staging checks pass, promote only the expected secret-free files:

```bash
install -m 0600 \
  "$INCOMING_ROOT/cyclecloud/cyclecloud-converge-1.log" \
  "$DEMO_EVIDENCE_DIR/cyclecloud-converge-1.log"
install -m 0600 \
  "$INCOMING_ROOT/cyclecloud/cyclecloud-converge-2.log" \
  "$DEMO_EVIDENCE_DIR/cyclecloud-converge-2.log"
install -m 0600 \
  "$INCOMING_ROOT/scheduler/scheduler-converge-1.log" \
  "$DEMO_EVIDENCE_DIR/scheduler-converge-1.log"
install -m 0600 \
  "$INCOMING_ROOT/scheduler/scheduler-converge-2.log" \
  "$DEMO_EVIDENCE_DIR/scheduler-converge-2.log"
install -m 0600 \
  "$INCOMING_ROOT/windows-admin/private-administration.json" \
  "$DEMO_EVIDENCE_DIR/private-administration.json"

install -d -m 0700 "$DEMO_EVIDENCE_DIR/burst-job"
find "$INCOMING_ROOT/scheduler/burst-job" -type f -maxdepth 1 \
  -exec install -m 0600 {} "$DEMO_EVIDENCE_DIR/burst-job/" \;
```

Keep incoming archives and manifests under `/state` until B10 succeeds. Never copy archives,
credentials, private keys, raw protected inputs, or unvalidated files into `/evidence`.

## B9. Collect audit evidence

Create a real structured validation summary; never mark an unexecuted check as successful:

```bash
export WORKSPACE_ID="<log-analytics-workspace-id>"
export PLAN_REFERENCE_FILE="$APPROVAL_FILE"
export VALIDATION_RESULTS_FILE="$DEMO_EVIDENCE_DIR/validation-results.json"
export EVIDENCE_DIR="$DEMO_EVIDENCE_DIR/audit"

install -d -m 0700 "$EVIDENCE_DIR"
if tests/end-to-end/collect_audit_evidence.sh; then
  AUDIT_EVIDENCE_STATUS=0
else
  AUDIT_EVIDENCE_STATUS="$?"
  printf 'Audit evidence collection failed with exit status %s; stop.\n' \
    "$AUDIT_EVIDENCE_STATUS" >&2
fi
test "$AUDIT_EVIDENCE_STATUS" -eq 0
```

Confirm the package contains 90-day validation, administration, secret-access, configuration,
cluster-lifecycle, and job evidence without secret values.

## B10. Prove final convergence

Run a final plan against unchanged inputs:

```bash
set +e
terraform -chdir=terraform plan \
  -input=false \
  -detailed-exitcode \
  -var-file="$TFVARS_FILE" \
  -no-color 2>&1 |
  tee "$DEMO_STATE_DIR/final-no-change-plan.log"
FINAL_PLAN_PIPE_STATUSES=("${PIPESTATUS[@]}")
FINAL_PLAN_STATUS="${FINAL_PLAN_PIPE_STATUSES[0]}"

test "$FINAL_PLAN_STATUS" -eq 0
test "${FINAL_PLAN_PIPE_STATUSES[1]}" -eq 0
```

For `-detailed-exitcode`, `0` means no changes, `1` means an error, and `2` means changes are
proposed. Record only the exit status and bounded no-change result in evidence; do not copy an
unreviewed raw plan.

Confirm Chef and template-processor reruns remain no-op, then record the completion time and
secret-scan result.

After B10 passes, execute A9 before continuing.

## B11. Remove the main deployment and verify dependent states

Return from A9 to the original operator shell. Re-establish the protected paths if necessary, then
remove the Bicep-owned CycleCloud VM before creating a distinct Terraform main-destroy plan. Never
use `terraform destroy -auto-approve`:

For a successful T057 run, execute B11 after B10 and A9. If B3 through B10 fails after Azure
resources may have been created, the acceptance run is permanently failed, but the operator may
still execute A9, then B11, then A10 to clean up safely. Set the A10 live-acceptance status to
`failed`; successful cleanup must never relabel the failed run as passed.

```bash
export TFVARS_FILE="$PWD/terraform/environments/demo.tfvars"
export DEMO_STATE_DIR="/state/slurm-demo/$RUN_ID"
export DEMO_EVIDENCE_DIR="/evidence/quickstart/$RUN_ID/slurm-demo"
export MAIN_DESTROY_PLAN="$DEMO_STATE_DIR/main-destroy.tfplan"
export MAIN_DESTROY_PLAN_DIGEST="$DEMO_STATE_DIR/main-destroy.tfplan.sha256"
export MAIN_DESTROY_STALE_PLAN="$DEMO_STATE_DIR/main-destroy-stale.tfplan"
export MAIN_DESTROY_STALE_LOG="$DEMO_STATE_DIR/main-destroy-stale.log"
export MAIN_DESTROY_INPUT_MANIFEST="$DEMO_STATE_DIR/main-destroy-inputs.json"
export MAIN_DESTROY_APPROVAL="$DEMO_STATE_DIR/main-destroy-approval.json"
export MAIN_DESTROY_APPROVAL_SCHEMA="$PWD/specs/003-terraform-backend-bootstrap/contracts/backend-plan-approval.schema.json"
export MAIN_CLEANUP_EVIDENCE="$DEMO_EVIDENCE_DIR/main-cleanup.json"

test -f "$TFVARS_FILE"
test "$SOURCE_COMMIT" = "$(git rev-parse HEAD)"
```

Snapshot the deployment stack, review that it owns only the CycleCloud VM, and record a distinct
cleanup approval:

```bash
tests/end-to-end/cyclecloud_stack.sh cleanup-plan

if read -r -p "Authorized CycleCloud stack cleanup reference: " \
  CYCLECLOUD_CLEANUP_APPROVAL_REFERENCE &&
  test -n "$CYCLECLOUD_CLEANUP_APPROVAL_REFERENCE"; then
  jq -n \
    --arg stack_snapshot_digest "$(
      sha256sum "$CYCLECLOUD_CLEANUP_PLAN_FILE" | awk '{print $1}'
    )" \
    --arg approval_reference "$CYCLECLOUD_CLEANUP_APPROVAL_REFERENCE" \
    '{
      stack_snapshot_digest: $stack_snapshot_digest,
      approval_reference: $approval_reference
    }' >"$CYCLECLOUD_CLEANUP_APPROVAL_FILE"
  chmod 0600 "$CYCLECLOUD_CLEANUP_APPROVAL_FILE"
fi

test -f "$CYCLECLOUD_CLEANUP_APPROVAL_FILE"
tests/end-to-end/cyclecloud_stack.sh cleanup
```

Stop if stack cleanup fails or if the CycleCloud VM remains. Only then capture Terraform state and
plan destruction of the Terraform-owned NIC and surrounding resources:

```bash

terraform -chdir=terraform state pull \
  >"$DEMO_STATE_DIR/main-state-before-destroy.json"
chmod 0600 "$DEMO_STATE_DIR/main-state-before-destroy.json"

if MAIN_PRE_DESTROY_ADDRESSES="$(terraform -chdir=terraform state list)"; then
  MAIN_PRE_DESTROY_STATE_STATUS=0
else
  MAIN_PRE_DESTROY_STATE_STATUS="$?"
fi
test "$MAIN_PRE_DESTROY_STATE_STATUS" -eq 0
export MAIN_PRE_DESTROY_RESOURCE_COUNT="$(
  awk 'NF {count++} END {print count + 0}' \
    <<<"$MAIN_PRE_DESTROY_ADDRESSES"
)"

jq -n \
  --arg source_commit "$SOURCE_COMMIT" \
  --arg tfvars_sha256 "$(sha256sum "$TFVARS_FILE" | awk '{print $1}')" \
  --arg state_lineage "$(
    jq -r '.lineage' "$DEMO_STATE_DIR/main-state-before-destroy.json"
  )" \
  --argjson managed_resource_count "$MAIN_PRE_DESTROY_RESOURCE_COUNT" \
  '{
    source_commit: $source_commit,
    tfvars_sha256: $tfvars_sha256,
    state_lineage: $state_lineage,
    managed_resource_count: $managed_resource_count
  }' >"$MAIN_DESTROY_INPUT_MANIFEST"
chmod 0600 "$MAIN_DESTROY_INPUT_MANIFEST"
```

Generate the saved destroy plan and capture failure without enabling `errexit`:

```bash
if terraform -chdir=terraform plan \
  -destroy \
  -input=false \
  -var-file="$TFVARS_FILE" \
  -out="$MAIN_DESTROY_PLAN"; then
  MAIN_DESTROY_PLAN_STATUS=0
  sha256sum "$MAIN_DESTROY_PLAN" >"$MAIN_DESTROY_PLAN_DIGEST"
  cp --preserve=mode "$MAIN_DESTROY_PLAN" "$MAIN_DESTROY_STALE_PLAN"
  chmod 0600 \
    "$MAIN_DESTROY_PLAN" \
    "$MAIN_DESTROY_PLAN_DIGEST" \
    "$MAIN_DESTROY_STALE_PLAN"
else
  MAIN_DESTROY_PLAN_STATUS="$?"
  printf 'Main destroy planning failed with exit status %s; stop.\n' \
    "$MAIN_DESTROY_PLAN_STATUS" >&2
fi
test "$MAIN_DESTROY_PLAN_STATUS" -eq 0
```

Mechanically reject an empty plan or any action other than deletion, then review the human-readable
plan:

```bash
export MAIN_DESTROY_CHANGE_SUMMARY="$(
  terraform -chdir=terraform show -json "$MAIN_DESTROY_PLAN" |
    jq -c '[
      .resource_changes[]? |
      select(.change.actions != ["no-op"]) |
      {address: .address, actions: .change.actions}
    ]'
)"

test "$(jq 'length' <<<"$MAIN_DESTROY_CHANGE_SUMMARY")" -gt 0
jq -e 'all(.[]; .actions == ["delete"])' \
  <<<"$MAIN_DESTROY_CHANGE_SUMMARY" >/dev/null
terraform -chdir=terraform show -no-color "$MAIN_DESTROY_PLAN"
```

Only after review, create a post-generation protected approval record:

```bash
if read -r -p "Authorized main cleanup reference: " \
  MAIN_DESTROY_APPROVAL_REFERENCE &&
  test -n "$MAIN_DESTROY_APPROVAL_REFERENCE"; then
  jq -n \
    --arg source_commit "$SOURCE_COMMIT" \
    --arg input_digest "$(
      sha256sum "$MAIN_DESTROY_INPUT_MANIFEST" | awk '{print $1}'
    )" \
    --arg plan_digest "$(sha256sum "$MAIN_DESTROY_PLAN" | awk '{print $1}')" \
    --arg plan_created_at "$(
      date -u -r "$MAIN_DESTROY_PLAN" +%Y-%m-%dT%H:%M:%SZ
    )" \
    --arg approved_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg approval_reference "$MAIN_DESTROY_APPROVAL_REFERENCE" \
    '{
      schema_version: "1.0",
      action: "destroy",
      source_commit: $source_commit,
      input_digest: $input_digest,
      plan_digest: $plan_digest,
      plan_created_at: $plan_created_at,
      approved_at: $approved_at,
      approval_reference: $approval_reference
    }' >"$MAIN_DESTROY_APPROVAL"
  chmod 0600 "$MAIN_DESTROY_APPROVAL"
else
  printf 'No main cleanup approval was recorded; stop.\n' >&2
fi
test -f "$MAIN_DESTROY_APPROVAL"

.venv/bin/python - "$MAIN_DESTROY_APPROVAL" "$MAIN_DESTROY_APPROVAL_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

approval = json.loads(Path(sys.argv[1]).read_text())
schema = json.loads(Path(sys.argv[2]).read_text())
Draft202012Validator(
    schema,
    format_checker=FormatChecker(),
).validate(approval)
PY
```

Revalidate every binding and apply only the exact approved plan:

```bash
sha256sum -c "$MAIN_DESTROY_PLAN_DIGEST"
test "$(jq -r '.source_commit' "$MAIN_DESTROY_APPROVAL")" = "$SOURCE_COMMIT"
test "$(jq -r '.input_digest' "$MAIN_DESTROY_APPROVAL")" = \
  "$(sha256sum "$MAIN_DESTROY_INPUT_MANIFEST" | awk '{print $1}')"
test "$(jq -r '.plan_digest' "$MAIN_DESTROY_APPROVAL")" = \
  "$(sha256sum "$MAIN_DESTROY_PLAN" | awk '{print $1}')"

if terraform -chdir=terraform apply \
  -input=false \
  "$MAIN_DESTROY_PLAN"; then
  MAIN_DESTROY_APPLY_STATUS=0
else
  MAIN_DESTROY_APPLY_STATUS="$?"
  printf 'Main cleanup apply failed with exit status %s; retain state and stop.\n' \
    "$MAIN_DESTROY_APPLY_STATUS" >&2
fi
test "$MAIN_DESTROY_APPLY_STATUS" -eq 0
```

Prove the duplicate saved plan is stale without allowing its expected failure to terminate the
shell:

```bash
set +e
MAIN_DESTROY_STALE_REJECTED="false"
terraform -chdir=terraform apply \
  -input=false \
  "$MAIN_DESTROY_STALE_PLAN" >"$MAIN_DESTROY_STALE_LOG" 2>&1
MAIN_DESTROY_STALE_STATUS="$?"

if test "$MAIN_DESTROY_STALE_STATUS" -eq 0; then
  printf 'The duplicate main destroy plan was unexpectedly accepted; stop.\n' >&2
else
  grep -Eiq 'saved plan is stale|state has changed' \
    "$MAIN_DESTROY_STALE_LOG"
  MAIN_DESTROY_STALE_REJECTED="true"
fi
test "$MAIN_DESTROY_STALE_STATUS" -ne 0
test "$MAIN_DESTROY_STALE_REJECTED" = "true"
```

Finally, verify that main and capacity-probe state are readable and empty, then emit bounded
dependent-cleanup evidence:

```bash
if MAIN_REMAINING_ADDRESSES="$(
  terraform -chdir=terraform state list \
    2>"$DEMO_STATE_DIR/main-state-list-after-cleanup.log"
)"; then
  MAIN_STATE_LIST_STATUS=0
else
  MAIN_STATE_LIST_STATUS="$?"
fi

if PROBE_REMAINING_ADDRESSES="$(
  terraform -chdir=terraform/capacity-probe state list \
    2>"$DEMO_STATE_DIR/probe-state-list-after-cleanup.log"
)"; then
  PROBE_STATE_LIST_STATUS=0
else
  PROBE_STATE_LIST_STATUS="$?"
fi

test "$MAIN_STATE_LIST_STATUS" -eq 0
test "$PROBE_STATE_LIST_STATUS" -eq 0
test -z "$MAIN_REMAINING_ADDRESSES"
test -z "$PROBE_REMAINING_ADDRESSES"

tee_output "$MAIN_CLEANUP_EVIDENCE" \
  jq -n \
    --arg source_commit "$SOURCE_COMMIT" \
    --arg completed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg plan_digest "$(sha256sum "$MAIN_DESTROY_PLAN" | awk '{print $1}')" \
    --arg approval_reference "$MAIN_DESTROY_APPROVAL_REFERENCE" \
    --argjson stale_plan_rejected "$MAIN_DESTROY_STALE_REJECTED" \
    '{
      schema_version: "1.0",
      source_commit: $source_commit,
      completed_at: $completed_at,
      main: {
        managed_resource_count: 0,
        destroy_plan_digest: $plan_digest,
        approval_reference: $approval_reference,
        applied_plan_digest_matches: true,
        stale_plan_rejected: $stale_plan_rejected
      },
      capacity_probe: {
        managed_resource_count: 0,
        cleanup_verified: true
      },
      status: "passed"
    }'
```

Do not return to A10 unless B11 ends with both dependent resource counts equal to zero.

## 3. Final acceptance and stop rules

Acceptance passes only when:

- the exact source commit and clean worktree were recorded;
- every validation command succeeded;
- backend bootstrap completed within 20 minutes of active execution excluding separately recorded
  role propagation and approval waits;
- local-to-remote migration, no-change, native lock conflict, and three isolated keys passed;
- final backend readiness is current and `ready`;
- replacement-operator recovery completed within 15 minutes without secret distribution;
- static preflight and exact-placement capacity probe passed and probe cleanup was verified;
- the exact approved main plan was applied within 90 minutes;
- all management endpoints remained private;
- both Chef second converges and the template second transformation were no-op;
- the one-node burst job completed in the approved burst region within 15 minutes and the idle
  node was removed;
- final Terraform planning reported no changes;
- state content and protected operational artifacts never entered evidence or Git; and
- secret scanning found zero credentials, tokens, storage keys, SAS values, certificate material,
  or protected inputs.

Stop immediately on validation, plan review, digest, stale-plan, quota, zonal eligibility,
capacity, probe cleanup, compatibility, migration, lock, private connectivity, identity,
certificate, secret access, idempotency, recovery, or cleanup failure.

Do not substitute versions, images, SKUs, regions, zones, state keys, identities, network modes,
or public endpoints. Do not manually patch a node or bypass a failed gate. Correct the approved
inputs or implementation, then begin a new assessment with new plans, evidence, and approvals.
