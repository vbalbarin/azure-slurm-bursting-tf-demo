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

1. Copy `terraform/environments/demo.tfvars.example` to a protected, ignored `.tfvars` file and
   supply the approved subscription, tenant, distinct source/burst regions, CIDRs, Entra group,
   exact scheduler and burst-compute image versions, VM SKUs, and versioned Key Vault references.
2. Export `SCHEDULER_URN` for the source-region standard AlmaLinux image and
   `BURST_COMPUTE_URN` for the burst-region AlmaLinux HPC image, then run
   `tests/end-to-end/preflight.sh`. Preserve its JSON output as compatibility evidence and pass its
   protected path to provisioning as `PREFLIGHT_RESULTS_FILE`. Provisioning rejects evidence whose
   role-specific URNs differ from the Terraform inventory. Stop on an unavailable or
   VM-size-incompatible image, mismatched AlmaLinux major release, unsupported service, quota,
   Marketplace terms, global peering, or regional capacity. Never substitute another image, SKU,
   or region automatically.
3. Run `make validate`, create and approve the saved plan as described above, then run
   `tests/end-to-end/provision.sh` to apply that exact digest and produce secret-free inventory.
4. Use Bastion to run `chef/bin/converge-cyclecloud.sh` and
   `chef/bin/converge-scheduler.sh` twice. The second run must report zero resources updated.
5. From the Windows administration VM reached through Bastion, run
   `tests/end-to-end/verify_private_administration.ps1`. The private CycleCloud URL must resolve,
   present the trusted Key Vault certificate, and show the imported cluster without public access.
6. On the scheduler, run `tests/end-to-end/run_burst_demo.sh`. The output must identify one node
   in the configured burst region within 15 minutes and that node must disappear after idle
   timeout while the source-region scheduler remains healthy.
7. Run `tests/end-to-end/collect_audit_evidence.sh`, validate inventory, and create a second
   unchanged Terraform plan. Any drift, secret leak, failed private probe, or non-idempotent result
   blocks completion.

Do not manually patch a node or bypass compatibility, identity, certificate, connectivity,
secret-access, idempotency, or reviewed-plan failures. Correct the input or implementation and
restart the invalidated gate.

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
