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
```

Record only non-secret run metadata:

```bash
export SOURCE_COMMIT="$(git rev-parse HEAD)"

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
  }' >"$RUN_EVIDENCE_DIR/run-metadata.json"

git --no-pager status --short >"$RUN_EVIDENCE_DIR/git-status.txt"
test ! -s "$RUN_EVIDENCE_DIR/git-status.txt"
```

Stop if the worktree is not clean. The evidence must identify the exact tested commit.

### 1.2 Authenticate to the approved Azure context

```bash
az login
az account set --subscription "<approved-subscription-id>"

az account show \
  --query '{subscription_id:id,subscription_name:name,tenant_id:tenantId,user_type:user.type}' \
  --output json >"$RUN_EVIDENCE_DIR/azure-account.json"
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

Edit `$BOOTSTRAP_TFVARS` with approved values from
[`backend-inputs.md`](../specs/003-terraform-backend-bootstrap/contracts/backend-inputs.md).
Set `source_commit` to `$SOURCE_COMMIT`. Do not add a storage key, SAS, access token, password, or
certificate.

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

sha256sum "$BOOTSTRAP_CREATE_PLAN" >"$BOOTSTRAP_CREATE_DIGEST"
sha256sum "$BOOTSTRAP_TFVARS" >"$BOOTSTRAP_STATE_DIR/bootstrap.tfvars.sha256"
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
  -no-color >"$BOOTSTRAP_STATE_DIR/create-no-change.log" 2>&1
BOOTSTRAP_NO_CHANGE_STATUS="$?"
set -e
test "$BOOTSTRAP_NO_CHANGE_STATUS" -eq 0
```

Do not copy the raw no-change log into evidence. Record only the exit status and bounded result.

## A4. Export canonical coordinates

```bash
terraform -chdir=terraform/bootstrap output -json backend_coordinates \
  >"$BACKEND_EVIDENCE_DIR/backend-coordinates.json"

sha256sum "$BACKEND_EVIDENCE_DIR/backend-coordinates.json" \
  >"$BACKEND_EVIDENCE_DIR/backend-coordinates.json.sha256"

export COORDINATES_DIGEST="$(
  sha256sum "$BACKEND_EVIDENCE_DIR/backend-coordinates.json" |
  awk '{print $1}'
)"
```

Validate the output against
[`backend-coordinates.schema.json`](../specs/003-terraform-backend-bootstrap/contracts/backend-coordinates.schema.json)
through `make backend-contract-test`. Confirm the bootstrap, main, and capacity-probe keys are
`<environment>/bootstrap.tfstate`, `<environment>/main.tfstate`, and
`<environment>/capacity-probe.tfstate`, and are pairwise distinct.

## A5. Perform preliminary readiness from the actual runner

Run each observation directly from the runner that will use the backend:

```bash
az account show \
  --query '{subscription_id:id,tenant_id:tenantId,user_type:user.type}' \
  --output json

az storage account show \
  --ids "<storage-account-resource-id>" \
  --query '{id:id,publicNetworkAccess:publicNetworkAccess,allowSharedKeyAccess:allowSharedKeyAccess}' \
  --output json

az storage container show \
  --auth-mode login \
  --account-name "<storage-account>" \
  --name tfstate \
  --query '{name:name}' \
  --output json

getent ahostsv4 "<storage-account>.blob.core.windows.net"

curl --fail-with-body --silent --show-error --head \
  "https://<storage-account>.blob.core.windows.net/tfstate?restype=container"

az storage blob list \
  --auth-mode login \
  --account-name "<storage-account>" \
  --container-name tfstate \
  --num-results 1 \
  --query 'length(@)'
```

Record only bounded, non-secret values in a protected assertions file under
`$BOOTSTRAP_STATE_DIR`, matching
[`backend-readiness-assertions.schema.json`](../specs/003-terraform-backend-bootstrap/contracts/backend-readiness-assertions.schema.json).
Use these exact stable command IDs:

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

Each observation contains its UTC time, exit code, `passed`, `failed`, or `not_run` status, and a
bounded non-secret value. Preliminary readiness permits only migration and locking to be
`not_run`, with null exit codes and empty observed values.

Bind the assertions to:

- `$SOURCE_COMMIT`;
- `$COORDINATES_DIGEST`;
- the active tenant and principal;
- the selected network mode;
- sorted resolved Blob IPv4 addresses;
- the observed public source IPv4 for restricted-public mode, or a canonical private-network
  context digest for private mode; and
- a SHA-256 digest of the canonical non-secret runner context.

A changed source address, route/context, identity, coordinate, or resolved endpoint invalidates
readiness and requires a new assessment. Put the assertions into the protected bootstrap inputs,
set `readiness_phase = "preliminary"`, create and approve an exact output plan, then apply only
that plan.

Export the native Terraform classification:

```bash
terraform -chdir=terraform/bootstrap output -json backend_readiness \
  >"$BACKEND_EVIDENCE_DIR/backend-readiness-preliminary.json"

sha256sum "$BACKEND_EVIDENCE_DIR/backend-readiness-preliminary.json" \
  >"$BACKEND_EVIDENCE_DIR/backend-readiness-preliminary.json.sha256"
```

Preliminary status is not final readiness. Stop on any failed or inconclusive applicable check.

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
terraform -chdir=terraform/bootstrap output -json backend_readiness \
  >"$BACKEND_EVIDENCE_DIR/backend-readiness.json"

sha256sum "$BACKEND_EVIDENCE_DIR/backend-readiness.json" \
  >"$BACKEND_EVIDENCE_DIR/backend-readiness.json.sha256"

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

Reverse-migrate bootstrap state to `/state` with `terraform init -migrate-state`; verify mode
`0600`, lineage, resource count, and digest before removing the AzureRM override.

Populate protected lifecycle assertions matching
[`backend-lifecycle.schema.json`](../specs/003-terraform-backend-bootstrap/contracts/backend-lifecycle.schema.json).
Then:

1. Set `lifecycle_action = "unlock"`.
2. Generate an unlock-only saved plan.
3. Calculate its digest after generation.
4. Obtain a post-generation approval with `action = "unlock"`.
5. Recheck source, input, and plan digests.
6. Apply only that exact unlock plan and confirm the lock is absent.
7. Set `lifecycle_action = "destroy"`.
8. Generate a separate destroy plan.
9. Obtain a separate approval with `action = "destroy"`.
10. Recheck all digests and apply only that exact destroy plan.
11. Verify the storage account and container are absent.

Any non-empty dependent state, failed reverse migration, wrong local-state mode, state-digest
mismatch, stale plan, or mismatched approval blocks removal.

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
tests/end-to-end/marketplace_terms.sh show "$TFVARS_FILE" \
  >"$DEMO_EVIDENCE_DIR/marketplace-terms.json"
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

tests/end-to-end/preflight.sh >"$PREFLIGHT_RESULTS_FILE"

tests/end-to-end/render_preflight_summary.sh \
  "$PREFLIGHT_RESULTS_FILE" \
  >"$DEMO_EVIDENCE_DIR/preflight-summary.md"
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

sha256sum "$PLAN_FILE" >"$DEMO_STATE_DIR/main.tfplan.sha256"
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
  -no-color >"$DEMO_STATE_DIR/final-no-change-plan.log" 2>&1
FINAL_PLAN_STATUS="$?"
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
