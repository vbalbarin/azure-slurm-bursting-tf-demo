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
```

Stop if the worktree is not clean. The evidence must identify the exact tested commit.

### 1.2 Authenticate to the approved Azure context

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
Bootstrap acceptance must complete within 20 minutes, excluding separately measured Entra
role-propagation delay.

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
BOOTSTRAP_NO_CHANGE_STATUS="${PIPESTATUS[0]}"
set -e
test "$BOOTSTRAP_NO_CHANGE_STATUS" -eq 0
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

export COORDINATES_DIGEST="$(
  sha256sum "$BACKEND_EVIDENCE_DIR/backend-coordinates.json" |
  awk '{print $1}'
)"
```

Validate the live output and record a bounded result:

```bash
export BACKEND_COORDINATES_FILE="$BACKEND_EVIDENCE_DIR/backend-coordinates.json"
export BACKEND_COORDINATES_SCHEMA="$PWD/specs/003-terraform-backend-bootstrap/contracts/backend-coordinates.schema.json"

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
    --arg document_digest "$COORDINATES_DIGEST" \
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
set -e
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
set -e
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
set -e
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
set -e
test "$DNS_EXIT" -eq 0

export RESOLVED_BLOB_IPV4_JSON="$(
  awk '{print $1}' <<<"$DNS_OUTPUT" |
    sort -u |
    jq -R . |
    jq -s .
)"
test "$(jq 'length' <<<"$RESOLVED_BLOB_IPV4_JSON")" -gt 0

export NETWORK_OBSERVED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
set +e
NETWORK_HTTP_STATUS="$(
  curl --ipv4 \
    --silent \
    --show-error \
    --head \
    --output /dev/null \
    --write-out '%{http_code}' \
    "https://$BLOB_HOST/$STATE_CONTAINER_NAME?restype=container"
)"
NETWORK_EXIT="$?"
set -e
test "$NETWORK_EXIT" -eq 0
case "$NETWORK_HTTP_STATUS" in
  200|400|401|403) ;;
  *) printf 'Unexpected Blob HTTP status: %s\n' "$NETWORK_HTTP_STATUS" >&2; false ;;
esac
```

An unauthenticated HTTP `403` is acceptable for the network check because it proves the private
container endpoint is reachable; the authenticated Blob command below separately proves
authorization. HTTP `000`, DNS failure, timeout, or transport failure blocks readiness.

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
set -e
test "$AUTHORIZATION_EXIT" -eq 0
case "$BLOB_RESULT_COUNT" in
  0|1) ;;
  *) printf 'Unexpected Blob query count: %s\n' "$BLOB_RESULT_COUNT" >&2; false ;;
esac

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
set -e
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
  --arg network_http_status "$NETWORK_HTTP_STATUS" \
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
        observed_value: ("http_status=" + $network_http_status)
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

rm terraform/bootstrap/backend.local.tf
cp terraform/bootstrap/backend.azurerm.tf.example \
  terraform/bootstrap/backend.azurerm.tf

terraform -chdir=terraform/bootstrap init \
  -migrate-state \
  -input=false \
  -backend-config="storage_account_name=<storage-account>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=$BACKEND_ENVIRONMENT/bootstrap.tfstate"
```

Use `-migrate-state`, never `-reconfigure`, when state must be copied.

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

Run a remote no-change plan and require status `0`. Then deliberately overlap two Terraform
operations against the bootstrap namespace and verify that the first acquires/releases the native
lock while the second is rejected with a lock conflict. Do not disable locking.

Record the migration result in a secret-free document matching
[`backend-migration-acceptance.schema.json`](../specs/003-terraform-backend-bootstrap/contracts/backend-migration-acceptance.schema.json).
Include state digests, lineage, resource counts, three distinct keys, no-change status, stale-plan
rejection, lock-conflict result, and confirmation that the local copy was retained until
verification. Never include state content.

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
recursive deletion. Confirm the recognized local state files are absent and record that result.

## A7. Produce final readiness

Update the protected assertions so migration and locking are `passed`, with their actual UTC
times, exit codes, stable command IDs, and bounded results. Set `readiness_phase = "final"`.
Recalculate the current runner-context digest immediately before planning and require it to match.

Create, review, approve, and apply an exact output-only plan, then export:

```bash
tee_output "$BACKEND_EVIDENCE_DIR/backend-readiness.json" \
  terraform -chdir=terraform/bootstrap output -json backend_readiness

tee_output "$BACKEND_EVIDENCE_DIR/backend-readiness.json.sha256" \
  sha256sum "$BACKEND_EVIDENCE_DIR/backend-readiness.json"

jq -e '.status == "ready" and .failure_class == "none"' \
  "$BACKEND_EVIDENCE_DIR/backend-readiness.json"

export ROLE_PROPAGATION_DELAY_SECONDS="<separately-measured-seconds>"
export BOOTSTRAP_COMPLETED_EPOCH="$(date +%s)"
export BOOTSTRAP_ELAPSED_SECONDS="$((
  BOOTSTRAP_COMPLETED_EPOCH -
  BOOTSTRAP_STARTED_EPOCH -
  ROLE_PROPAGATION_DELAY_SECONDS
))"
test "$BOOTSTRAP_ELAPSED_SECONDS" -le 1200
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

Within 15 minutes, the replacement operator must directly:

1. resolve and reach the selected Blob endpoint;
2. initialize the bootstrap, main, and capacity-probe namespaces;
3. read each state; and
4. acquire and release a native lock in each namespace.

Do not distribute a storage key, SAS, copied token, or shared credential. Record only the
replacement principal ID/type, tenant, authenticated/completed times, elapsed seconds, and
per-namespace Boolean results required by
[`backend-live-acceptance.schema.json`](../specs/003-terraform-backend-bootstrap/contracts/backend-live-acceptance.schema.json).

## A10. Validate managed removal

Existing mode has no unlock or backend-destroy operation.

For managed mode, first prove that main and capacity-probe state are readable and contain zero
managed resources. Destroy and verify those environments separately before backend removal.

The procedure below covers an abandoned managed deployment whose bootstrap state never left the
protected local backend. It does not claim local-to-remote-to-local acceptance. If state was
migrated to Azure Blob, stop and reverse-migrate it with `terraform init -migrate-state` before
using the unlock and destroy steps. In that case use
`state_migration_status = "reverse_migrated"` and
`reverse_migration_verified = true`.

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

install -d -m 0700 "$REMOVAL_EVIDENCE_DIR"

test -f "$BOOTSTRAP_TFVARS"
test -f "$BOOTSTRAP_LOCAL_STATE"
test "$(stat -c '%a' "$BOOTSTRAP_LOCAL_STATE")" = "600"
test -f terraform/bootstrap/backend.local.tf
test ! -e terraform/bootstrap/backend.azurerm.tf
test "$SOURCE_COMMIT" = "$(git rev-parse HEAD)"

terraform -chdir=terraform/bootstrap init \
  -reconfigure \
  -input=false \
  -backend-config="path=$BOOTSTRAP_LOCAL_STATE"
```

The last two backend-file checks prove this path is applicable only while the configured backend is
local. They do not prove that remote migration never happened if files were manually changed.
Review the stopped run’s migration evidence and state history before continuing.

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
existence; do not copy state content into evidence:

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

test "$MAIN_STATE_EXISTS" = "false"
test "$PROBE_STATE_EXISTS" = "false"

export MAIN_STATE_STATUS="absent"
export MAIN_MANAGED_RESOURCE_COUNT="0"
export PROBE_STATE_STATUS="absent"
export PROBE_MANAGED_RESOURCE_COUNT="0"
```

If either result is `true`, stop. Initialize that dependent root, inspect its state, and separately
destroy and verify it before returning to A10. Do not relabel an existing state blob as absent.

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

Use a distinct external approval reference for unlock. The reference identifies the accountable
review, but approval of the exact digest occurs only after plan generation:

```bash
read -r -p "Authorized unlock review reference: " \
  UNLOCK_APPROVAL_REFERENCE
test -n "$UNLOCK_APPROVAL_REFERENCE"

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
      state_migration_status: "never_migrated",
      reverse_migration_verified: false
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

from jsonschema import Draft202012Validator, FormatChecker, RefResolver

evidence = json.loads(Path(sys.argv[1]).read_text())
schema_path = Path(sys.argv[2])
schema = json.loads(schema_path.read_text())
schema["$id"] = schema_path.resolve().as_uri()
resolver = RefResolver(
    base_uri=schema["$id"],
    referrer=schema,
)
Draft202012Validator(
    schema,
    resolver=resolver,
    format_checker=FormatChecker(),
).validate(evidence)
PY

test "$(jq -r '.status' "$UNLOCK_LIFECYCLE_EVIDENCE")" = "ready"
test "$(jq -r '.action' "$UNLOCK_LIFECYCLE_EVIDENCE")" = "unlock"
test "$(jq -r '.bootstrap_state.migration_status' "$UNLOCK_LIFECYCLE_EVIDENCE")" = \
  "never_migrated"
test "$(jq -r '.bootstrap_state.reverse_migration_verified' "$UNLOCK_LIFECYCLE_EVIDENCE")" = \
  "false"

test "$(
  az lock list \
    --scope "$STORAGE_ACCOUNT_RESOURCE_ID" \
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
set -e

test "$UNLOCK_STALE_STATUS" -ne 0
grep -Fq "Saved plan is stale" "$UNLOCK_STALE_LOG"
export UNLOCK_STALE_PLAN_REJECTED="true"
```

### A10.6 Generate a separate destroy plan

Use a different approval reference and a new lifecycle input file. Rebind the expected digest to
the post-unlock local state:

```bash
read -r -p "Authorized destroy review reference: " \
  DESTROY_APPROVAL_REFERENCE
test -n "$DESTROY_APPROVAL_REFERENCE"
test "$DESTROY_APPROVAL_REFERENCE" != "$UNLOCK_APPROVAL_REFERENCE"

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
      state_migration_status: "never_migrated",
      reverse_migration_verified: false
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
DESTROY_PRINTF_STATUS="${PIPESTATUS[0]}"
DESTROY_CONSOLE_STATUS="${PIPESTATUS[1]}"
DESTROY_JQ_STATUS="${PIPESTATUS[2]}"
DESTROY_TEE_STATUS="${PIPESTATUS[3]}"
set -e

test "$DESTROY_PRINTF_STATUS" -eq 0
test "$DESTROY_CONSOLE_STATUS" -eq 0
test "$DESTROY_JQ_STATUS" -eq 0
test "$DESTROY_TEE_STATUS" -eq 0

.venv/bin/python - \
  "$DESTROY_LIFECYCLE_EVIDENCE" \
  "$LIFECYCLE_SCHEMA" <<'PY'
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker, RefResolver

evidence = json.loads(Path(sys.argv[1]).read_text())
schema_path = Path(sys.argv[2])
schema = json.loads(schema_path.read_text())
schema["$id"] = schema_path.resolve().as_uri()
resolver = RefResolver(
    base_uri=schema["$id"],
    referrer=schema,
)
Draft202012Validator(
    schema,
    resolver=resolver,
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
set -e

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
```

Do not delete the protected local state, plans, approvals, manifests, or raw stale-plan logs until
the bounded removal evidence has been reviewed and retained according to policy.

Any non-empty dependent state, unverified state provenance, wrong local-state mode, state-digest
mismatch, unexpected plan action, stale plan accepted, mismatched approval, or ambiguous Azure
absence result blocks removal.

Record bootstrap, preliminary readiness, migration/final readiness, dependent initialization and
deployment, recovery, unlock, and removal as separate stages. Acceptance requires zero
undocumented commands and zero workflow substitutions.

---

# Part B: Slurm bursting demo

Part B assumes Part A produced current final backend readiness and initialized the main and
capacity-probe roots.

## B1. Prepare the protected demo inputs

```bash
export TFVARS_FILE="$PWD/terraform/environments/demo.tfvars"

cp terraform/environments/demo.tfvars.example "$TFVARS_FILE"
chmod 0600 "$TFVARS_FILE"
git check-ignore -v "$TFVARS_FILE"
```

Edit the file with approved:

- subscription, tenant, and existing Entra security-group object IDs;
- distinct source and burst regions;
- one explicit burst zone and ordered approved alternate placements;
- private CIDRs;
- exact role counts and VM SKUs;
- independent exact scheduler and burst-compute image URNs from the same AlmaLinux family and
  major release;
- pinned CycleCloud `8.9.3` and Windows image;
- versioned Key Vault references and other protected inputs.

Do not copy the `.tfvars` file into `/evidence`.

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

tee_output "$PREFLIGHT_RESULTS_FILE" \
  tests/end-to-end/preflight.sh

tee_output "$DEMO_EVIDENCE_DIR/preflight-summary.md" \
  tests/end-to-end/render_preflight_summary.sh \
    "$PREFLIGHT_RESULTS_FILE"
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
```

Edit `$PROBE_TFVARS_FILE` with the exact selected subscription, tenant, environment, burst
region, zone, SKU, image, current backend-readiness file, source commit, active principal,
execution-context digest, an expiration no more than 24 hours ahead, accountable owner, and
`cost_acknowledged = true`. These values must match the static preflight and protected demo
inputs.

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
tests/end-to-end/capacity_probe.sh apply
```

Require one exact burst node to allocate within 15 minutes. Create and separately approve cleanup:

```bash
tests/end-to-end/capacity_probe.sh cleanup-plan
tests/end-to-end/capacity_probe.sh cleanup

jq -e \
  '.allocation_state == "allocated" and .cleanup_state == "verified"' \
  "$PROBE_EVIDENCE_DIR/capacity-probe.json"
```

Stop if allocation or cleanup fails. Probe success is point-in-time evidence, not a future or
multi-node capacity guarantee.

## B4. Create and review the main saved plan

Use protected state for the saved plan and approval:

```bash
export PLAN_FILE="$DEMO_STATE_DIR/main.tfplan"
export APPROVAL_FILE="$DEMO_STATE_DIR/main-plan-approval.json"
export CAPACITY_PROBE_RESULTS_FILE="$PROBE_EVIDENCE_DIR/capacity-probe.json"

terraform -chdir=terraform validate

terraform -chdir=terraform plan \
  -input=false \
  -var-file="$TFVARS_FILE" \
  -out="$PLAN_FILE"

tee_output "$DEMO_STATE_DIR/main.tfplan.sha256" \
  sha256sum "$PLAN_FILE"
terraform -chdir=terraform show -no-color "$PLAN_FILE"
```

Review interactively and confirm:

- only pinned providers and direct pinned AVM calls appear;
- no direct Azure resource or local custom Terraform module appears;
- no VM, CycleCloud endpoint, or Key Vault public endpoint is planned;
- exactly two VNETs and bidirectional global peerings are planned;
- exactly three persistent VMs and one Bastion host are planned;
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
  "approval_reference": "<approved change or review reference>"
}
```

Any source, input, backend context, selected placement, plan, or evidence change invalidates
approval.

## B5. Apply the exact reviewed main plan

`provision.sh` consumes the existing plan and never regenerates it:

```bash
export EVIDENCE_DIR="$DEMO_EVIDENCE_DIR"

tests/end-to-end/provision.sh
```

The script verifies all three approved digests, rejects stale preflight evidence, applies only
`$PLAN_FILE`, enforces the 90-minute target, and writes:

```text
$DEMO_EVIDENCE_DIR/inventory.json
$DEMO_EVIDENCE_DIR/provisioning.json
```

Validate the secret-free inventory and private infrastructure:

```bash
run_logged "$DEMO_EVIDENCE_DIR/20-inventory-validation.log" \
  python3 tests/end-to-end/verify_inventory.py \
  "$DEMO_EVIDENCE_DIR/inventory.json"

export INVENTORY_FILE="$DEMO_EVIDENCE_DIR/inventory.json"
run_logged "$DEMO_EVIDENCE_DIR/21-infrastructure-validation.log" \
  tests/end-to-end/verify_infrastructure.sh
```

Confirm provisioning completes within 90 minutes, public-inbound probes fail, and CycleCloud and
Key Vault resolve privately from authorized locations.

## B6. Converge CycleCloud and scheduler twice

Through Bastion, run:

- `chef/bin/converge-cyclecloud.sh` twice on the CycleCloud VM; and
- `chef/bin/converge-scheduler.sh` twice on the scheduler.

The second run on each host must report zero updated resources. Confirm CycleCloud `8.9.3`, the
pinned Slurm project/version, role-specific images, services, identities, `/sched`, `/shared`, and
the headless-template contracts.

`/evidence` exists only in the development container. Capture logs to a protected temporary
directory on each VM, then transfer them through an approved protected channel into:

```text
$DEMO_EVIDENCE_DIR/cyclecloud-converge-1.log
$DEMO_EVIDENCE_DIR/cyclecloud-converge-2.log
$DEMO_EVIDENCE_DIR/scheduler-converge-1.log
$DEMO_EVIDENCE_DIR/scheduler-converge-2.log
```

Do not use `set -x`; the convergence path consumes protected references and credential material.

## B7. Verify private Windows administration

Connect to the Windows administration VM only through Azure Bastion. Run:

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

Transfer the resulting secret-free JSON through an approved protected channel into
`$DEMO_EVIDENCE_DIR`.

## B8. Run the one-node burst job

On the scheduler, from the checked-out repository, use a protected temporary evidence directory:

```bash
export DEMO_USERNAME="<demo-user>"
export PARTITION="<slurm-partition>"
export SOURCE_REGION="<source-region>"
export BURST_REGION="<burst-region>"
export IDLE_TIMEOUT_MINUTES="<idle-timeout>"
export DEMO_UID_GID="<numeric-demo-uid>"
export EVIDENCE_DIR="<protected-temporary-directory-on-scheduler>"

tests/end-to-end/run_burst_demo.sh 2>&1 |
  tee "$EVIDENCE_DIR/run-burst-demo.log"

test "${PIPESTATUS[0]}" -eq 0
```

Require, within 15 minutes under normal regional capacity:

1. the job moves from queued to configuring/running;
2. one CycleCloud compute node appears;
3. the job completes on that node;
4. output under the shared home identifies the execution node in the configured burst region
   while the scheduler remains in the source region; and
5. the node disappears after the configured idle timeout while scheduler health remains good.

Transfer the resulting evidence through an approved protected channel into
`$DEMO_EVIDENCE_DIR/burst-job/`.

## B9. Collect audit evidence

Create a real structured validation summary; never mark an unexecuted check as successful:

```bash
export WORKSPACE_ID="<log-analytics-workspace-id>"
export PLAN_REFERENCE_FILE="$APPROVAL_FILE"
export VALIDATION_RESULTS_FILE="$DEMO_EVIDENCE_DIR/validation-results.json"
export EVIDENCE_DIR="$DEMO_EVIDENCE_DIR/audit"

install -d -m 0700 "$EVIDENCE_DIR"
tests/end-to-end/collect_audit_evidence.sh
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
FINAL_PLAN_STATUS="${PIPESTATUS[0]}"
set -e

test "$FINAL_PLAN_STATUS" -eq 0
```

For `-detailed-exitcode`, `0` means no changes, `1` means an error, and `2` means changes are
proposed. Record only the exit status and bounded no-change result in evidence; do not copy an
unreviewed raw plan.

Confirm Chef and template-processor reruns remain no-op, then record the completion time and
secret-scan result.

## 3. Final acceptance and stop rules

Acceptance passes only when:

- the exact source commit and clean worktree were recorded;
- every validation command succeeded;
- backend bootstrap completed within 20 minutes excluding separately recorded role propagation;
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
