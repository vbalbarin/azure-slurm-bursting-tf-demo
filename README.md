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

## Goals

- Place the Slurm scheduler and administration plane in a configurable Azure source region and
  burst compute into a separately configurable Azure region with less constrained capacity.
- Connect the two regional virtual networks through private cross-region peering.
- Use only pinned AVM modules for Azure resources.
- Keep all VM and service management paths private through Azure Bastion and private endpoints.
- Configure the CycleCloud and scheduler hosts through idempotent Chef Local policies.
- Generate a release-matched headless Slurm cluster definition without manual editing.
- Demonstrate one Slurm job bursting to a transient remote compute node.
- Protect credentials and certificates in Azure Key Vault.
- Require infrastructure, configuration, security, and idempotency validation before deployment.

## Current Design

The approved design includes:

- Azure CycleCloud `8.9.3`, pinned during planning
- External Slurm scheduler on an exact-version standard AlmaLinux image
- Independently pinned AlmaLinux HPC image for burst compute
- Windows administration host
- Azure Bastion
- Azure Key Vault with public network access disabled
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
redesigned around Terraform, Azure Verified Modules, Chef Local, private Azure access, explicit
security controls, and repeatable validation.

The conceptual progression is:

1. Study the original script-driven demonstration and its operational workflow.
2. Define independent governance and security requirements.
3. Express the desired behavior as a testable feature specification.
4. Research and design an AVM-only Azure architecture.
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
   composition, the distinct source and burst regions, no public management endpoints, no
   unintended replacement or deletion, and redacted sensitive values.
4. Record the reviewer approval reference beside the digest in `$EVIDENCE_DIR`.
5. Apply only with `terraform -chdir=terraform apply <approved-plan-path>`.

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

1. Copy `terraform/environments/demo.tfvars.example` to a protected, ignored `.tfvars` file and
   supply the approved subscription, tenant, distinct source/burst regions, CIDRs, Entra group,
   exact scheduler and burst-compute image versions, VM SKUs, and versioned Key Vault references.
2. Source `tests/end-to-end/export_preflight_env.sh` with the protected `.tfvars` path. The helper
   uses Terraform and `jq` to export and display only the non-secret role sizes, counts, image URNs,
   selected zone, and approved alternate placements. Use
   `tests/end-to-end/marketplace_terms.sh show "$TFVARS_FILE"` to review the exact CycleCloud legal
   links and acceptance state. If acceptance is required, an authorized operator must deliberately
   run the `accept` action with `ACCEPT_MARKETPLACE_TERMS=yes`; export and preflight never accept
   legal terms implicitly. Then run `tests/end-to-end/preflight.sh` and preserve stdout as
   `PREFLIGHT_RESULTS_FILE`. Review its separate total-regional and VM-family quota measurements,
   selected-zone restrictions, and ordered alternate-placement assessments. A candidate result is
   advisory and never changes deployment inputs.
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
8. Run `tests/end-to-end/collect_audit_evidence.sh`, validate inventory, and create a second
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
