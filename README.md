# Azure Slurm Bursting Terraform Demo

This project demonstrates Slurm cloud bursting into Microsoft Azure through Azure CycleCloud.
It defines the Azure control plane with Terraform and Azure Verified Modules (AVM), configures
infrastructure nodes with Chef Local, and validates changes before deployment.

The project is currently in the specification and design phase. Implementation will follow the
approved Spec Kit artifacts under [`specs/002-slurm-bursting-demo/`](specs/002-slurm-bursting-demo/).

## Development container

Open the repository in VS Code and select **Dev Containers: Reopen in Container**. The image build
installs operating-system prerequisites as root inside the disposable image; the
[`post-create.sh`](.devcontainer/post-create.sh) setup then runs as the non-root `vscode` user and
installs pinned Python and Ruby dependencies into workspace-local `.venv/` and `.bundle/`
directories. No host-level `sudo` access is required.

The container pins Terraform, TFLint, Azure CLI, PowerShell, Ruby, Chef Infra Client, ChefSpec,
Cookstyle, Test Kitchen, InSpec, Checkov, pytest, mypy, Bandit, `uv`, and the Spec Kit CLI. Run:

```text
specify --version
make validate
make chef-style
make chef-unit
```

`make chef-integration` creates Azure Test Kitchen resources and therefore still requires an
authorized `az login`, an approved subscription, accepted product terms, and protected
environment inputs. The container deliberately does not mount host Azure credentials or accept
Chef licensing terms automatically.

### Protected evidence volume

The development container creates the Docker volume
`azure-slurm-bursting-tf-demo-evidence` and mounts it at `/evidence`. The volume is outside the Git
workspace, persists across container rebuilds, and is writable only by the container's `vscode`
user. The container sets:

```text
EVIDENCE_ROOT=/evidence
EVIDENCE_DIR=/evidence/quickstart
```

The post-create setup creates `/evidence/quickstart` with mode `0700`. Evidence-producing commands
can therefore use `EVIDENCE_DIR` without writing plans, logs, audit events, or other protected
artifacts into the repository:

```bash
printf '%s\n' "$EVIDENCE_DIR"
test -d "$EVIDENCE_DIR" && test -w "$EVIDENCE_DIR"
```

Use the detailed
[`quickstart-evidence-runbook.md`](docs/quickstart-evidence-runbook.md) for the complete backend
bootstrap and Slurm demo evidence workflow.

Rebuild the development container after changing its configuration so the volume is mounted. A
named volume is used instead of a host-home bind mount to keep the configuration portable across
Linux, macOS, Windows, Codespaces, and remote Docker hosts. It is not automatically backed up.
Export required evidence to an approved protected location before removing the Docker volume or
development environment. Evidence created on provisioned VMs must be transferred through an
approved protected channel into `$EVIDENCE_DIR`; `/evidence` is mounted only in the development
container.

The post-create command checks the mount whenever the development container is created or rebuilt.
Restarting an existing container does not normally rerun that command. Because the named volume
persists across rebuilds, rebuilding does not reset its contents; post-create adjusts retained
ownership to the current `vscode` user when necessary.

If post-create reports that `/evidence` is not writable, inspect the volume from the host:

```bash
docker run --rm \
  --mount source=azure-slurm-bursting-tf-demo-evidence,target=/evidence \
  alpine ls -ldn /evidence
```

Dev Containers can remap the `vscode` user's UID and GID to match the host account. Consequently,
hard-coding `1000:1000` can leave the volume inaccessible. The post-create command automatically
changes the volume contents to the `vscode` user's current UID and GID without deleting them.

To repair the currently running container before rebuilding, run this inside the container:

```bash
sudo chown -R "$(id -u):$(id -g)" /evidence
chmod 0700 /evidence
```

Alternatively, rebuild the development container to rerun the automatic repair. If the evidence is
no longer needed, removing the named volume and rebuilding is another option, but permanently
deletes everything stored in the volume. Do not create `$HOME/evidence`; it is not used by this
configuration.

### Terraform state backend bootstrap

The development container also mounts the named volume
`azure-slurm-bursting-tf-demo-state` at `/state`. It is separate from `/evidence`, is repaired to
the current container user's ownership on create/rebuild, and is restricted to mode `0700`.
Bootstrap state, saved plans, readiness assertions, lifecycle assertions, and approval records are
protected operational inputs; they must not be committed or copied into evidence.

The independent [`terraform/bootstrap/`](terraform/bootstrap/) root either creates a governed
backend through direct pinned Azure Verified Modules or validates approved existing coordinates.
Managed mode creates a private `tfstate` container, Entra data-plane assignments, restricted
networking, versioning and seven-day deletion recovery, and a `CanNotDelete` lock. Existing mode
performs read-only lookups and creates, imports, changes, locks, unlocks, and destroys nothing.

#### 1. Create and apply an exact reviewed backend plan

Copy [`bootstrap.tfvars.example`](terraform/bootstrap/bootstrap.tfvars.example) to an ignored
`.tfvars` file and replace placeholders with approved values. For private mode, supply an existing
reachable subnet and the `privatelink.blob.core.windows.net` private DNS zone. Do not add a public
CIDR fallback. Then initialize protected local state:

```bash
umask 077
export BACKEND_ENVIRONMENT="demo"
export BOOTSTRAP_STATE_DIR="${BOOTSTRAP_STATE_ROOT}/${BACKEND_ENVIRONMENT}"
install -d -m 0700 "$BOOTSTRAP_STATE_DIR"
cp terraform/bootstrap/backend.local.tf.example terraform/bootstrap/backend.local.tf
terraform -chdir=terraform/bootstrap init \
  -reconfigure \
  -backend-config="path=${BOOTSTRAP_STATE_DIR}/terraform.tfstate"
terraform -chdir=terraform/bootstrap validate
```

Create the plan under `/state`, calculate its digest only after generation, and create a protected
approval record conforming to
[`backend-plan-approval.schema.json`](specs/003-terraform-backend-bootstrap/contracts/backend-plan-approval.schema.json):

```bash
terraform -chdir=terraform/bootstrap plan \
  -var-file="$BOOTSTRAP_STATE_DIR/bootstrap.tfvars" \
  -out="$BOOTSTRAP_STATE_DIR/create.tfplan"
sha256sum "$BOOTSTRAP_STATE_DIR/create.tfplan"
sha256sum -c "$BOOTSTRAP_STATE_DIR/create.tfplan.sha256"
terraform -chdir=terraform/bootstrap apply "$BOOTSTRAP_STATE_DIR/create.tfplan"
terraform -chdir=terraform/bootstrap plan \
  -var-file="$BOOTSTRAP_STATE_DIR/bootstrap.tfvars" \
  -detailed-exitcode
```

The reviewer must verify the exact source/input/plan digests and expected AVM-only changes.
Immediately recheck the plan digest before `apply`; Terraform separately rejects a saved plan whose
state snapshot is stale. Never replace exact-plan apply with auto-approval.

#### 2. Assess readiness from the actual runner

Run observations directly; do not implement readiness, provisioning, lifecycle, or apply in a
custom Bash/Python wrapper. Record only bounded, non-secret values in a protected assertions file
conforming to
[`backend-readiness-assertions.schema.json`](specs/003-terraform-backend-bootstrap/contracts/backend-readiness-assertions.schema.json):

```bash
az account show --query '{subscription_id:id,tenant_id:tenantId,user_type:user.type}' -o json
az storage account show --ids "<storage-account-resource-id>" \
  --query '{id:id,publicNetworkAccess:publicNetworkAccess,allowSharedKeyAccess:allowSharedKeyAccess}'
az storage container show --auth-mode login \
  --account-name "<storage-account>" --name tfstate --query '{name:name}'
getent ahostsv4 "<storage-account>.blob.core.windows.net"
curl --fail-with-body --silent --show-error --head \
  "https://<storage-account>.blob.core.windows.net/tfstate?restype=container"
az storage blob list --auth-mode login \
  --account-name "<storage-account>" --container-name tfstate \
  --num-results 1 --query 'length(@)'
terraform -chdir=terraform/bootstrap state pull >/dev/null
```

Use stable command IDs documented in the readiness assertion contract. Capture UTC observation
times, exit codes, `passed`/`failed`/`not_run`, and bounded observed values—not raw output. Bind the
assertions to the canonical coordinate digest, source commit, active tenant/identity, network
mode, resolved Blob IPv4 addresses, and a SHA-256 of the non-secret runner context. Restricted
public mode records the observed public source IPv4; private mode records the private-network
context digest. A changed source address, route/context, or resolved endpoint requires reassessment.
Role-assignment propagation delay is recorded separately and is never treated as success.

Set `readiness_phase = "preliminary"` before migration; only migration and locking may be
`not_run`, with null exit codes and empty observed values. Apply an exact reviewed output plan,
export `terraform output -json backend_readiness` as canonical JSON, and create an adjacent
`.sha256`. Final evidence is valid for at most one hour.

#### 3. Migrate bootstrap state and initialize isolated roots

Retain the mode-`0600` local copy until remote pull, lineage/resource-count equality, a no-change
plan, and locking are verified. Replace the ignored local backend block with the ignored AzureRM
block and migrate; `-reconfigure` does not copy state and must not be used here:

```bash
rm terraform/bootstrap/backend.local.tf
cp terraform/bootstrap/backend.azurerm.tf.example terraform/bootstrap/backend.azurerm.tf
terraform -chdir=terraform/bootstrap init -migrate-state -input=false \
  -backend-config="storage_account_name=<storage-account>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=${BACKEND_ENVIRONMENT}/bootstrap.tfstate"
terraform -chdir=terraform/bootstrap state pull >/dev/null
```

Run a deliberate concurrent plan to prove the second operation receives a lock conflict. Update
migration and locking assertions to `passed`, regenerate final readiness, and remove the retained
local copy only after every verification succeeds. Active local state is the configured
`$BOOTSTRAP_STATE_DIR/terraform.tfstate`; recognized backups are the sibling
`terraform.tfstate.backup` and timestamped Terraform backup variants created for that state.
Record only SHA-256 digests and the named-file disposition in migration acceptance evidence—never
state or backup content. Delete only those named active/recognized files, confirm each is absent,
and retain that absence result. Sanitization of blocks on the named volume's underlying physical
media is the host/container platform's responsibility, not a claim made by this workflow.

Initialize the dependent roots with tracked Entra-only partial configurations:

```bash
cp terraform/backend.hcl.example terraform/backend.hcl
terraform -chdir=terraform init -reconfigure -input=false \
  -backend-config=backend.hcl

cp terraform/capacity-probe/backend.hcl.example terraform/capacity-probe/backend.hcl
terraform -chdir=terraform/capacity-probe init -reconfigure -input=false \
  -backend-config=backend.hcl
```

The exact keys are `<environment>/main.tfstate` and
`<environment>/capacity-probe.tfstate`. Both plans require the current readiness file, exact source
commit, and freshly calculated execution-context digest. Missing, malformed, stale, failed, or
mismatched evidence blocks planning before Azure resources are evaluated.

#### 4. Recovery and managed removal

Recovery grants a replacement operator membership in the approved Entra group; do not distribute a
storage key or SAS. After refreshing Azure login and allowing separately measured RBAC propagation,
the replacement operator must directly initialize, read, and lock all three namespaces.

Existing mode has no removal path. For managed removal:

1. Prove main and capacity-probe state are readable and manage zero resources.
2. If bootstrap state was migrated, migrate it back to protected local state with
   `terraform init -migrate-state`; otherwise prove that the authoritative state never left the
   protected local backend. Verify mode `0600`, lineage/resource count, and state digest before
   removing any AzureRM override.
3. Set lifecycle action `unlock`, create an unlock-only saved plan, create a post-generation
   approval record, verify its digest, and apply that exact plan.
4. Confirm the lock is absent. Set lifecycle action `destroy`, create a separate `-destroy` plan,
   obtain a separate approval, verify its digest, and apply only that plan.

For a combined backend and Slurm run, retain the managed backend through dependent initialization,
deployment, and cleanup. Perform managed removal only after main and capacity-probe state are
verified empty. Separate unlock and destroy approval records may use one external change ticket
when that ticket records both distinct post-generation approval events.

Any missing/inconsistent local state, non-empty dependent namespace, failed reverse migration,
state-digest mismatch, stale plan, or mismatched approval blocks removal.

For acceptance, record bootstrap, preliminary-readiness, migration/final-readiness, dependent
initialization/deployment, recovery, unlock, and removal as separate stages with their approval
references. Use only the commands documented above: acceptance requires zero undocumented
recovery commands and zero workflow substitutions.

## Goals

- Place the Slurm scheduler and administration plane in a configurable Azure source region and
  burst compute into a separately configurable Azure region with less constrained capacity.
- Connect the two regional virtual networks through private cross-region peering.
- Use pinned AVM modules for every Terraform-owned Azure resource and a narrowly scoped Bicep
  deployment stack only for the released CycleCloud Marketplace VM.
- Keep all VM and service management paths private through Azure Bastion and private endpoints.
- Configure the CycleCloud and scheduler hosts through idempotent Chef Local policies.
- Generate a release-matched headless Slurm cluster definition without manual editing.
- Demonstrate one Slurm job bursting to a transient remote compute node.
- Protect credentials and certificates in Azure Key Vault.
- Require infrastructure, configuration, security, and idempotency validation before deployment.

## Current Design

The approved design includes:

- Azure CycleCloud `8.9.3`, pinned during planning and deployed as a VM-only Bicep stack because
  its released Marketplace image requires an image data disk at LUN 0
- External Slurm scheduler on an exact-version standard AlmaLinux image
- Independently pinned AlmaLinux HPC image for burst compute
- Windows administration host
- Azure Bastion
- Azure Key Vault with a temporary approved runner `/32` for initial secret creation and mandatory
  private-only hardening before acceptance
- Private DNS and bidirectional VNET peering
- Independently selectable source and burst regions with fail-closed regional-capacity preflight
- Log Analytics with 90-day audit retention
- Chef Local for guest configuration
- A guarded Python processor for the CycleCloud headless-template transformation

See:

- [Project constitution](.specify/memory/constitution.md)
- [Feature specification](specs/002-slurm-bursting-demo/spec.md)
- [Implementation plan](specs/002-slurm-bursting-demo/plan.md)
- [Research decisions](specs/002-slurm-bursting-demo/research.md)
- [Data model](specs/002-slurm-bursting-demo/data-model.md)
- [Validation quickstart](specs/002-slurm-bursting-demo/quickstart.md)
- [Interface contracts](specs/002-slurm-bursting-demo/contracts/)

## Project History and Provenance

The concept was inspired by Vinil Vadakkepurakkal's
[`slurm-cloud-bursting-using-cyclecloud`](https://github.com/vinil-v/slurm-cloud-bursting-using-cyclecloud)
demonstration, which documents a script-based approach to configuring an external Slurm scheduler
and Azure CycleCloud.

This repository is a clean-history, independently authored evolution of that concept. It does not
contain commits or source files copied from Vinil's repository. The architecture is being
redesigned around Terraform, Azure Verified Modules, one governed CycleCloud VM-only Bicep
boundary, Chef Local, private Azure access, explicit security controls, and repeatable validation.

The conceptual progression is:

1. Study the original script-driven demonstration and its operational workflow.
2. Define independent governance and security requirements.
3. Express the desired behavior as a testable feature specification.
4. Research and design an AVM-based Azure architecture with one explicit Marketplace appliance
   exception where the approved Terraform VM module cannot express the released image.
5. Implement and validate the new solution independently.

The original repository remains the authoritative source for Vinil's implementation and history.

## Development Workflow

Spec Kit artifacts govern implementation:

1. Review the constitution and active feature specification.
2. Generate implementation tasks with `/speckit-tasks`.
3. Implement through `/speckit-implement`.
4. Run all required validation before creating or applying a deployment plan.

No deployment should proceed unless the exact configuration passes the validation gates defined in
the constitution and implementation plan.

### Reviewed-plan gate

1. Run the repository validation targets against the exact commit and environment inputs intended
   for deployment.
2. Create a saved plan with `terraform -chdir=terraform plan -out=<approved-plan-path>`; never
   place the plan in source control.
3. Record `sha256sum <approved-plan-path>` and have an authorized reviewer confirm AVM-only
   Terraform composition, the distinct source and burst regions, the bounded Key Vault
   provisioning `/32`, no public host endpoints, no unintended replacement or deletion, and
   redacted sensitive values.
4. Record the reviewer approval reference beside the digest in `$EVIDENCE_DIR`.
5. Apply only with `terraform -chdir=terraform apply <approved-plan-path>`.

The CycleCloud VM has a separate gate: compile the source-controlled Bicep template, derive its
parameters from Terraform outputs, review and approve the exact what-if digest, and deploy it
through a resource-group deployment stack. After initial secret creation, a second exact Terraform
plan must remove the Key Vault runner `/32` and disable public access. Provisioning is incomplete
until both the CycleCloud stack and Key Vault hardening gates pass.

Any change to Terraform, providers, modules, input values, backend/state context, Chef policy, or
the template processor invalidates the applicable validation evidence and saved-plan approval.
Regenerate and review the plan rather than substituting a region, SKU, image, topology, or public
endpoint. A failed validation, review, digest comparison, or approval check blocks deployment.

### End-to-end operator workflow

> [!IMPORTANT]
> CycleCloud-managed resources are not implicitly zonal. This demonstration explicitly pins the
> burst node array to one availability zone to make SKU checks, the capacity probe, and acceptance
> evidence deterministic. Availability-zone placement is a fault-domain and allocation constraint;
> it does not by itself guarantee minimum compute, storage, or MPI latency. Tightly coupled
> workloads can also require supported RDMA networking, proximity placement, and appropriately
> co-located storage. Conversely, zone pinning can reduce allocation flexibility when capacity
> exists elsewhere in the region. The cross-region scheduler-hosted `/sched` and `/shared` exports
> in this bounded one-node demo are not a production low-latency HPC storage design.

#### Operator identity prerequisite

`operator_group_object_ids` must contain at least one existing Microsoft Entra security-group
object ID from the configured tenant. Use the group object ID, not its display name, an application
ID, or an individual user ID. Terraform grants each listed group `Key Vault Secrets Officer` on
the demonstration vault so authorized humans can retrieve, update, rotate, and recover demo
secrets.

This group is separate from the identity that runs Terraform:

- The Terraform identity needs permission to create the resource group, infrastructure, and role
  assignments. Subscription `Owner`, or an appropriately scoped combination such as `Contributor`
  plus `Role Based Access Control Administrator`, can satisfy that deployment role.
- Subscription `Owner` is control-plane authority and does not by itself imply Key Vault secret
  data-plane access. An owner can create the required assignment, but must belong to a listed group
  or receive another suitable Key Vault data-plane role to read secret values.
- The automated Slurm job, CycleCloud allocation, and idle-node removal path does not depend on
  human group membership after configuration. The group remains the supported human administration
  and recovery path, so removing its vault assignment after setup is not part of this design.

RBAC assignments can take several minutes to propagate after deployment.

For the evidence run, the agent executes A1-A8, A11, B1-B5, the CycleCloud stack gate, and the Key
Vault hardening gate. The operator then gathers
host-local B6-B8 evidence through Bastion native-client sessions. After the protected incoming
artifacts are available, the agent validates them and executes B9-B10, A9, B11, and A10. Native
SSH/SCP and RDP clients are required for this handoff; browser-only Bastion access is not the
evidence-transfer channel.

1. Copy `terraform/environments/demo.tfvars.example` to a protected, ignored `.tfvars` file and
   supply the approved subscription, tenant, distinct source/burst regions, CIDRs, Entra group,
   exact scheduler and burst-compute image versions, VM SKUs, the approved runner `/32`, and
   versioned Key Vault references.
2. Source `tests/end-to-end/export_preflight_env.sh` with the protected `.tfvars` path. The helper
   uses Terraform and `jq` to export and display only the non-secret role sizes, counts, image URNs,
   selected zone, and approved alternate placements. Use
   `tests/end-to-end/marketplace_terms.sh show "$TFVARS_FILE"` to review the exact CycleCloud legal
   links and acceptance state. If acceptance is required, an authorized operator must deliberately
   run the `accept` action with `ACCEPT_MARKETPLACE_TERMS=yes`; export and preflight never accept
   legal terms implicitly. Then run `tests/end-to-end/preflight.sh` and preserve stdout as
   `PREFLIGHT_RESULTS_FILE`. Run
   `tests/end-to-end/render_preflight_summary.sh "$PREFLIGHT_RESULTS_FILE"` to render a Markdown
   summary for VS Code preview. Review its separate total-regional and VM-family quota
   measurements, selected-zone restrictions, all detected blockers, and ordered
   alternate-placement assessments. The JSON remains the authoritative evidence. A candidate
   result is advisory and never changes deployment inputs.
3. Explicitly acknowledge temporary Azure cost and run
   `tests/end-to-end/capacity_probe.sh plan` against `terraform/capacity-probe/`. Review and approve
   its saved plan, run `apply`, then create and approve the destroy plan before running `cleanup`.
   Continue only when `capacity-probe.json` records one exact allocation and verified cleanup.
   Success is point-in-time evidence, not a future or multi-node capacity guarantee. Use an
   On-demand Capacity Reservation when guaranteed placement is required.
4. Run `make validate`, create the main saved plan, and approve its plan digest together with the
   exact preflight and cleaned-probe evidence digests. Run `tests/end-to-end/provision.sh`; it
   consumes the existing reviewed plan and never regenerates it. Any changed input, selected
   region/zone, plan, or evidence file invalidates approval.
5. Use Bastion to run `chef/bin/converge-cyclecloud.sh` and
   `chef/bin/converge-scheduler.sh` twice. The second run must report zero resources updated.
6. From the Windows administration VM reached through Bastion, run
   `tests/end-to-end/verify_private_administration.ps1`. The private CycleCloud URL must resolve,
   present the trusted Key Vault certificate, and show the imported cluster without public access.
7. On the scheduler, run `tests/end-to-end/run_burst_demo.sh`. The output must identify one node
   in the configured burst region within 15 minutes and that node must disappear after idle
   timeout while the source-region scheduler remains healthy.
8. Use the Premium private-only Bastion native-client tunnel to stage Linux evidence archives
   under `/state/slurm-demo/<run-id>/incoming/`. Verify safe archive paths, SHA-256 manifests, and
   secret-pattern scans before promoting only expected files into `/evidence`. Transfer the
   Windows JSON through the Bastion RDP protected-drive handoff; never use the `tfstate` container.
   The pinned Bastion module does not support tunneling and session recording together, so this
   transfer mode disables session recording and relies on protected transfer artifacts for audit.
9. Run `tests/end-to-end/collect_audit_evidence.sh`, validate inventory, and create a second
   unchanged Terraform plan. Any drift, secret leak, failed private probe, or non-idempotent result
   blocks completion.

Do not manually patch a node or bypass quota, zonal eligibility, probe cleanup, compatibility,
identity, certificate, connectivity, secret-access, idempotency, or reviewed-plan failures. To
select an alternate placement, update the protected inputs and restart static preflight, capacity
probe, main-plan review, and approval.

### Private CycleCloud administration

Connect to the Windows administration VM only through Azure Bastion. Browse to the
`cyclecloud_private_url` from the generated inventory and authenticate with the authorized
CycleCloud application identity whose credential is retrieved through approved Key Vault access.
Confirm the certificate names the private endpoint and chains to the trusted private issuer before
opening the configured cluster. Use the cluster page to inspect its configuration and transient
node state. A public client must not resolve or connect to this endpoint.

If access fails, verify the private DNS links to both VNETs, global peering, NSG port 443, the
installed issuer chain, certificate expiration/name, and authorized application identity. Do not
enable public access as a workaround.

## Repository Status

Infrastructure and node-configuration implementation has not started. The next workflow step is:

```text
/speckit-tasks
```

## License

No license has been selected for this independently authored project yet. All rights are reserved
unless and until a license is added.
