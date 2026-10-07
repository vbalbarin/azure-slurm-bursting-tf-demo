# Azure Slurm Bursting Terraform Demo

This project demonstrates Slurm cloud bursting into Microsoft Azure through Azure CycleCloud.
It defines the Azure control plane with Terraform and Azure Verified Modules (AVM), configures
infrastructure nodes with Chef Local, and validates changes before deployment.

The project is currently in the specification and design phase. Implementation will follow the
approved Spec Kit artifacts under [`specs/002-slurm-bursting-demo/`](specs/002-slurm-bursting-demo/).

## Goals

- Simulate an on-premises Slurm scheduler and a remote Azure CycleCloud environment with two
  peered virtual networks.
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
- AlmaLinux HPC external Slurm scheduler
- Windows administration host
- Azure Bastion
- Azure Key Vault with public network access disabled
- Private DNS and bidirectional VNET peering
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

## Repository Status

Infrastructure and node-configuration implementation has not started. The next workflow step is:

```text
/speckit-tasks
```

## License

No license has been selected for this independently authored project yet. All rights are reserved
unless and until a license is added.
