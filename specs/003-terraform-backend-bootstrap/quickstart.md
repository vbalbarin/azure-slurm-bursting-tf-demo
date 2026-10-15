# Quickstart Validation Guide

This guide defines the acceptance sequence for the backend-bootstrap feature after implementation.
It does not replace an environment-specific reviewed plan, approval record, or operational runbook.

Review [research.md](./research.md), [data-model.md](./data-model.md), and every file under
[contracts/](./contracts/) before live validation.

## Prerequisites

- Approved Azure tenant, subscription, and bootstrap region
- Operator with management-plane permission to create managed-mode resources and role assignments
- Existing approved Entra operator security group
- Optional approved workload identity for automation
- Four-to-six-character lowercase alphanumeric uniqueness code
- Approved workload, environment, instance, tags, and region code
- For restricted-public mode, explicit current public IPv4 CIDRs
- For private managed mode, an existing reachable subnet and Blob private DNS zone
- For private existing mode, approved equivalent network coordinates in `existing_backend`
- For either private path, working DNS and routing from the actual runner
- Development container rebuilt with separate writable `/state` and `/evidence` named volumes
- Protected ignored bootstrap input file matching
  [backend-inputs.md](./contracts/backend-inputs.md)

State may contain sensitive values. Never copy state, state backups, plans, or access tokens into
ordinary logs. Only the secret-free artifacts explicitly identified below belong in `/evidence`.

Execute every Terraform or Azure migration, provisioning, apply, unlock, and destroy command
directly as shown in this guide. Python acceptance tests may validate the resulting schema-bound,
secret-free evidence only; they must not invoke Terraform, Azure CLI, or any control-plane
operation.

For a combined backend and workload acceptance, execute sections 1 through 7, retain the managed
backend while dependent workloads run, and execute section 8 only after those workloads have been
destroyed and both dependent namespaces are empty. A backend-only acceptance may proceed directly
through section 8, but it leaves no backend for dependent deployment.

## 1. Validate source

Run the repository validation entry points covering:

```text
Terraform formatting and validation for all three roots
Terraform native bootstrap tests
Terraform lint and security policy
AVM-only policy tests
Backend input and JSON contract tests
Native Terraform readiness and lifecycle classification tests
JSON Schema tests for coordinates, readiness, lifecycle, and post-generation approval records
```

Expected outcome:

- Every command succeeds.
- Managed restricted-public, managed private, and existing validate-only fixtures pass.
- Invalid naming, network, identity, and ownership combinations fail before planning.
- No direct Azure resource or custom Terraform module is present.

## 2. Prepare protected local state

Create a new state workspace outside the Git repository and evidence volume:

```bash
umask 077
export BOOTSTRAP_STATE_DIR="/state/terraform-backend/<environment>"
install -d -m 0700 "$BOOTSTRAP_STATE_DIR"
test -w "$BOOTSTRAP_STATE_DIR"
cp terraform/bootstrap/backend.local.tf.example terraform/bootstrap/backend.local.tf
terraform -chdir=terraform/bootstrap init \
  -reconfigure \
  -backend-config="path=$BOOTSTRAP_STATE_DIR/terraform.tfstate"
```

Confirm `terraform/bootstrap/backend.local.tf` and all files under `$BOOTSTRAP_STATE_DIR` are
ignored. The local state file must remain mode `0600`; neither Git nor the evidence directory may
contain it.

## 3. Create and review the managed-backend plan

Initialize the bootstrap root without activating its remote backend:

```bash
terraform -chdir=terraform/bootstrap init -backend=false
terraform -chdir=terraform/bootstrap validate
```

Create a saved plan using the protected bootstrap inputs and protected local state location. Review
the plan and verify:

- only pinned resource-group and storage-account AVMs are called;
- the generated names match the approved ALZ naming components;
- the state container is private;
- shared-key and anonymous access are disabled;
- restricted-public mode uses default-deny plus only approved IPv4 CIDRs, or private mode disables
  public access and uses the approved subnet/DNS zone;
- the operator group and optional workload identity receive container-scoped Blob data access;
- versioning, seven-day soft delete, encryption, TLS, HTTPS, tags, and `CanNotDelete` lock are set;
- no secret or credential appears.

The implemented plan sequence is:

```bash
terraform -chdir=terraform/bootstrap plan \
  -var-file="$BOOTSTRAP_STATE_DIR/bootstrap.tfvars" \
  -out="$BOOTSTRAP_STATE_DIR/create.tfplan"
sha256sum "$BOOTSTRAP_STATE_DIR/create.tfplan" \
  >"$BOOTSTRAP_STATE_DIR/create.tfplan.sha256"
sha256sum -c "$BOOTSTRAP_STATE_DIR/create.tfplan.sha256"
terraform -chdir=terraform/bootstrap apply "$BOOTSTRAP_STATE_DIR/create.tfplan"
```

After the saved plan exists, calculate its SHA-256 digest and create an external approval record
matching [backend-plan-approval.schema.json](./contracts/backend-plan-approval.schema.json). Verify
the source commit, protected-input digest, and saved-plan digest immediately before applying only
that saved plan. Terraform must independently accept the saved plan's state snapshot as current.
A changed digest or stale plan blocks apply. A second unchanged plan must report no changes.

For existing mode, skip resource creation and prove that the plan creates, imports, mutates, locks,
and deletes nothing.

## 4. Validate pre-migration readiness

Run the documented Azure CLI, DNS, and HTTP inspection commands directly. Record only their
non-secret results in a protected document matching
[backend-readiness-assertions.schema.json](./contracts/backend-readiness-assertions.schema.json).
Each observation records the stable command ID, time, exit code, status, and bounded non-secret
value. Record the observed public source IPv4 address for restricted-public mode or a canonical
private-network context digest for private mode, plus resolved Blob addresses and the resulting
runner-context digest. Create and review a saved Terraform plan that validates freshness and
context binding and classifies those assertions through native locals, checks, and preconditions.
Do not use a custom Bash/Python readiness helper.

Expected outcome:

- active tenant/subscription match;
- account and container exist;
- DNS resolution matches the selected network mode;
- the endpoint is reachable from the actual runner;
- approved operator-group/workload-identity assignments are present;
- the active identity can perform required Blob operations through Entra authentication;
- all three keys are environment-scoped and pairwise distinct;
- status is not yet final until migration and lock verification pass.

Stop on any failed or inconclusive check. Never enable unrestricted public access as a fallback.
After applying the exact reviewed readiness-output plan, export the canonical readiness output as
JSON matching [backend-readiness.schema.json](./contracts/backend-readiness.schema.json) and create
an adjacent `.sha256` sidecar with `sha256sum`. The digest is not embedded in its own JSON document.
Before either dependent plan, recalculate the current protected execution-context digest and
require it to match readiness evidence. A changed source address, private-network context, or
resolved endpoint invalidates readiness and requires a new assessment.

## 5. Migrate bootstrap state to Azure Blob

Preserve the local state with mode `0600` and record only its digest in evidence. Install the
ignored AzureRM backend override from the tracked example, then initialize with:

```bash
rm terraform/bootstrap/backend.local.tf
cp terraform/bootstrap/backend.azurerm.tf.example terraform/bootstrap/backend.azurerm.tf
terraform -chdir=terraform/bootstrap init -migrate-state -input=false \
  -backend-config="storage_account_name=<storage-account>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=<environment>/bootstrap.tfstate"
```

Run `terraform init -migrate-state` with non-secret partial backend configuration. Do not use
`-reconfigure`, because it does not copy state.

Verify:

1. remote state can be pulled through the approved identity;
2. protected local and remote state lineage/resource counts agree;
3. an unchanged remote plan reports no changes and acquires/releases the native state lock;
4. a deliberate concurrent lock test rejects the second operation;
5. the protected assertions are updated with those results;
6. an exact reviewed output-only plan records final readiness;
7. final readiness JSON reports every check `passed`.

Only after all checks pass may the retained local state copy be securely removed. Preserve its
digest, not its content, as evidence.

## 6. Initialize dependent roots

Initialize:

```bash
cp terraform/backend.hcl.example terraform/backend.hcl
terraform -chdir=terraform init -reconfigure -input=false \
  -backend-config=backend.hcl

cp terraform/capacity-probe/backend.hcl.example terraform/capacity-probe/backend.hcl
terraform -chdir=terraform/capacity-probe init -reconfigure -input=false \
  -backend-config=backend.hcl
```

The files must contain exact keys `<environment>/main.tfstate` and
`<environment>/capacity-probe.tfstate`. Both roots must use Entra authentication and consume final
readiness evidence. Attempt plans with:

- valid readiness evidence;
- missing evidence;
- evidence older than one hour;
- a different source commit;
- different backend coordinates;
- failed status;
- colliding state keys.

Only the valid case may proceed to resource planning.

## 7. Recover another operator

Add a second authorized operator to the approved group, refresh that operator's Azure session, and
verify within 15 minutes that the operator can:

- resolve and reach the selected endpoint;
- initialize all three state namespaces;
- read state and acquire a lock;
- do so without a storage key, SAS, or copied credential.

## 8. Validate managed removal gates

Removal must initially fail while either main or capacity-probe state records managed resources.
After both dependent environments are separately destroyed and verified empty:

1. if bootstrap state was migrated, migrate it back to protected local state with
   `terraform init -migrate-state`; otherwise verify that the authoritative state never left the
   local backend;
2. verify the local state and remove the ignored remote-backend override when present;
3. create, review, approve, and apply an unlock-only plan;
4. create and review a separate destroy plan;
5. apply only the approved destroy plan;
6. verify backend resources are absent while protected removal evidence remains.

Existing mode exposes no unlock or backend-destroy operation.

For a combined run, removal is the final cleanup step after dependent workload acceptance. It is
not a prerequisite for initializing or deploying those workloads.

## 9. Final acceptance

Acceptance passes only when:

- source validation passes;
- measured bootstrap duration is at most 20 minutes after separately excluding recorded
  role-propagation delay;
- managed and existing modes satisfy their ownership boundaries;
- local→remote→local migration is demonstrated;
- second plans are no-change;
- native lock conflict is demonstrated;
- readiness classifications fail closed;
- all three state keys remain distinct;
- a replacement operator succeeds without secret distribution;
- measured replacement-operator recovery is at most 15 minutes;
- changed plan digests and stale saved plans are rejected;
- state content never enters evidence;
- managed removal is blocked until dependent state is empty;
- final secret scanning reports zero credentials, tokens, storage keys, SAS values, or protected
  demo inputs.
