# Implementation Plan: Automated Chef Bootstrap and Convergence

**Branch**: `005-automated-chef-bootstrap` | **Date**: 2026-10-27 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-automated-chef-bootstrap/spec.md`

## Summary

Deliver small, deterministic, role-specific Chef policy bundles and non-secret node specifications
through each VM's Azure custom-data document. Cloud-init verifies the bundle and pinned Chef Infra
Client package before staging an immutable local execution environment. The CycleCloud VM uses a
system-assigned orchestrator identity; Terraform creates Microsoft's reviewed custom role during
foundation, then applies a separately reviewed post-create plan after the VM principal exists.
The independently created locker UAMI remains available to cluster nodes. CycleCloud first-run
waits for bounded authorization checks and then invokes CycleCloud Chef convergence automatically.
A governed Azure VM Run Command workflow
invokes scheduler convergence only after CycleCloud and secret-access gates pass. The scheduler
emits a value-free `hpcuser01` public-identity receipt; a governed manual CycleCloud UI gate uses
the supported product interface to enable matching node access before burst acceptance.

## Technical Context

**Language/Version**: Terraform 1.13.3, Bicep 0.38.33, Bash 5, Python 3.12,
Ruby through Chef Infra Client 18.11.11  
**Primary Dependencies**: AzureRM 4.49.0, pinned Azure Verified Modules, CycleCloud 8.9.3,
Chef Infra Client 18.11.11, CycleCloud Slurm 4.0.11, repository `headless-template` package  
**Storage**: Existing private Key Vault for protected runtime inputs; VM-local `/opt/slurm-demo`
for immutable staged content and `/var/lib/slurm-demo` for state/evidence; existing CycleCloud
locker storage for CycleCloud project content  
**Testing**: Terraform validate/test, Bicep build and what-if validation, Pytest, ShellCheck,
ChefSpec, Cookstyle, Test Kitchen/InSpec, governed live rebuild and repeated-convergence checks  
**Target Platform**: AlmaLinux 9 scheduler VM and Azure CycleCloud 8.9.3 Marketplace appliance on
Azure; burst compute in the approved secondary region  
**Project Type**: Infrastructure-as-code plus local guest-configuration policies  
**Performance Goals**: Bootstrap-state inspection in under one minute; no unbounded polling;
one-node burst acceptance remains the capacity ceiling  
**Constraints**: 65,535-byte decoded Azure custom-data limit; no VM public IPs; no Chef Server;
no Terraform provisioners; no secrets in custom data, Terraform state, source, or evidence;
one identical-input in-place retry only; exact Microsoft CycleCloud custom-role permission set;
custom role assigned at the approved burst subscription scope; role assignments created only by
pinned AVM; post-create RBAC plan required because the system principal is unknown before VM
creation; first-boot authorization wait bounded to 30 minutes

**Scale/Scope**: Two persistent Linux VMs, one CycleCloud cluster, one nonprivileged demo user,
and one transient burst node

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Pre-design evaluation | Post-design evaluation |
|---|---|---|
| I. Compliance-Preserving Legacy Operation | PASS: the change automates the accepted Slurm bursting demonstration without adding HA, DR, or scale. | PASS: one scheduler, one CycleCloud appliance, and one transient burst node remain the bounded topology. |
| II. Declarative Infrastructure and Managed Node Configuration | PASS: Terraform/Bicep retain Azure ownership, Chef retains substantive guest steady state, and governed scripts only validate, package, dispatch approved entry points, and collect evidence. | PASS: the VM-only Bicep stack owns the system identity as part of the VM; Terraform owns the independent locker UAMI, custom role, and every role assignment; scripts invoke only exact reviewed Terraform plans and stack artifacts. |
| III. Azure Verified Modules and CycleCloud Appliance Exception | PASS: existing pinned root AVMs remain the Terraform boundary and the VM-only Bicep exception remains unchanged. | PASS: constitution v3.3.0 permits exactly one direct `azurerm_role_definition` because no AVM creates custom role definitions; pinned `Azure/avm-res-authorization-roleassignment/azurerm` v0.3.1 owns all post-create assignments. |
| IV. Security Without Exception | PASS: no public IP, public secret, unverified artifact, or standing vault write is planned; `azslurm initconfig` is the documented narrow product-interface exception. | PASS: the exact Microsoft CycleCloud custom role is assigned only at the approved burst subscription scope; vault read is separate; the independent locker UAMI has only storage blob read; bounded management, user-delegation, and secret-read checks fail closed. |
| V. Reliable, Idempotent, and Validated Change | PASS: immutable Policyfile locks, state, retries, reboot behavior, timing, and zero-update convergence are testable before live deployment. | PASS: contracts and quickstart require native validation, one identical-input retry, atomic state/evidence, sub-minute inspection, reboot safety, and final no-change proof. |

No unjustified constitutional violation remains.

## Project Structure

### Documentation (this feature)

```text
specs/005-automated-chef-bootstrap/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── artifact-manifest.schema.json
│   ├── bootstrap-state.schema.json
│   ├── convergence-evidence.schema.json
│   ├── node-specification.schema.json
│   ├── governed-workflow.md
│   └── cyclecloud-user-ui-gate.md
└── tasks.md
```

### Source Code (repository root)

```text
chef/
├── bootstrap/
│   └── linux.sh
├── bin/
│   ├── converge-cyclecloud.sh
│   ├── converge-scheduler.sh
│   ├── publish-hpc-user-receipt.sh
│   └── retrieve-key-vault-secret.py
├── cookbooks/
│   ├── cyclecloud_node/
│   └── slurm_scheduler/
├── policyfiles/
│   ├── cyclecloud.rb
│   ├── cyclecloud.lock.json
│   ├── slurm.rb
│   └── slurm.lock.json
└── test/
    └── integration/

infra/cyclecloud/
├── bootstrap.sh
├── main.bicep
└── modules/

terraform/
├── compute.tf
├── cyclecloud-platform.tf
├── cyclecloud-identity.tf
├── locals.tf
├── security.tf
├── variables.tf
└── outputs.tf

tests/
├── end-to-end/
│   ├── build_chef_policy_bundles.sh
│   ├── converge_linux_roles.sh
│   └── lib/
├── terraform/
└── unit/

docs/
└── quickstart-evidence-runbook.md
```

**Structure Decision**: Extend the existing Terraform root, Bicep VM boundary, Chef cookbooks, and
governed end-to-end workflow. Build role bundles deterministically under protected run state and
pass their Base64 payloads and manifests to VM custom data. Do not add an artifact storage account,
Chef Server, Terraform provisioner, custom Terraform module, or second Terraform state. Use an
explicit phase variable in the existing root so the foundation plan omits VM-principal-dependent
assignments and the post-create plan derives the principal from the deployed VM before adding only
the approved AVM-managed assignments.

## Phase 0: Research Outcomes

Research is complete in [research.md](./research.md). It resolves artifact delivery, package
pinning, Slurm release selection, secret retrieval, the `azslurm` credential boundary,
the `hpcuser01` public-identity receipt and governed UI gate, dependency dispatch, retry behavior,
idempotency evidence, system-assigned orchestrator ownership, the Microsoft custom-role contract,
the same-state post-create RBAC phase, authorization propagation, teardown ordering, and the
Microsoft Entra ID P1 preflight.

## Phase 1: Design Outcomes

- [data-model.md](./data-model.md) defines artifacts, node specifications, dependency gates,
  orchestrator RBAC receipts, identity receipts, manual user-gate attestations, attempts, state
  transitions, and evidence.
- [contracts/](./contracts/) defines machine-validated manifests, role inputs, state, evidence,
  the CycleCloud identity/RBAC receipt, and the governed infrastructure/dispatch sequence.
- [quickstart.md](./quickstart.md) defines the executable validation path from deterministic bundle
  build through clean-boot and second-run proof.

## Complexity Tracking

| Exception | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Root-only transient password argument to `azslurm initconfig` | The release-matched vendor CLI has no password-file, stdin, or environment option. | Hand-writing `autoscale.json` would depend on unsupported internal schema; patching the vendor package would create an unmaintained fork. |
| Azure VM Run Command as scheduler dispatch and public-key receipt transport | VMs have no public ingress and scheduler convergence must wait for CycleCloud. | Polling from cloud-init races dependencies; SSH from the runner violates the access boundary; standing orchestration software is unnecessary for two nodes. |
| Governed manual CycleCloud user gate | CycleCloud 8.9.3 documents application-user and cluster-access management only through its UI. | Its CLI manages cloud-provider accounts, not application users; its REST API has no user resource; the internal datastore is undocumented and cannot provide a versioned payload contract. |
| Direct Terraform CycleCloud custom-role definition | Microsoft publishes the required least-privilege permission set, but no AVM creates custom role definitions; constitution v3.3.0 authorizes exactly this one resource. | Built-in Contributor is broader; Bicep role creation violates the VM-only boundary; manual creation is not declarative or state-owned. |
| Bounded first-boot authorization wait | The system principal is created with the VM, so Terraform cannot assign its roles before boot starts. | A control UAMI violates the selected architecture; unbounded polling hides failures; Bicep role assignments violate Terraform ownership. |

## Implementation Sequence

Feature `004-user-friendly-passwords` is an implementation prerequisite. Its generator must
produce or preserve the protected credential set, validate cross-credential uniqueness for newly
generated values, and emit a value-free accepted receipt before feature 005 clean-boot testing.
Feature 005 consumes the existing `cyclecloud-admin-password` Key Vault reference and must not
generate or rotate that credential.

1. Complete and validate feature 004's protected credential-generation prerequisite.
2. Generate and verify immutable role-specific Policyfile lock files, then add deterministic
   role-bundle construction, JSON schema validation, custom-data size gates, and pinned package
   manifest generation.
3. Refactor common bootstrap to verify and install Chef, atomically stage content, lock execution,
   and write environment-ready state without logging protected values.
4. Replace the CycleCloud control UAMI with the VM system identity, retain the independent locker
   UAMI, define the exact Microsoft custom role, and add the explicit same-state post-create RBAC
   phase, identity receipt, bounded authorization gate, and pre-delete assignment-removal phase.
5. Extend CycleCloud custom data to wait for approved authorization, dispatch first-run, run
   CycleCloud Chef convergence, and verify cluster import.
6. Extend scheduler custom data and RBAC to stage only; add managed-identity Key Vault REST
   retrieval and protected `azslurm` initialization.
7. Replace `slurmdemo` with `hpcuser01` UID/GID 11200 and add idempotent scheduler SSH-key
   generation.
8. Add the governed dependency check, scheduler dispatch, digest-bound public-identity receipt,
   manual CycleCloud UI gate, explicit existing-VM policy staging/update path, one-retry limit,
   second-convergence checks, and evidence capture.
9. Update the governed runbook and execute targeted tests, approved infrastructure deployment,
   named VM rebuilds, administrative login checks, reboot safety checks, one-node burst, final
   Terraform no-change acceptance, and final CycleCloud deployment-stack what-if reconciliation.
