# Implementation Plan: Automated Chef Bootstrap and Convergence

**Branch**: `005-automated-chef-bootstrap` | **Date**: 2026-10-23 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/005-automated-chef-bootstrap/spec.md`

## Summary

Deliver small, deterministic, role-specific Chef policy bundles and non-secret node specifications
through each VM's Azure custom-data document. Cloud-init verifies the bundle and pinned Chef Infra
Client package before staging an immutable local execution environment. CycleCloud first-run then
invokes CycleCloud Chef convergence automatically. A governed Azure VM Run Command workflow
invokes scheduler convergence only after CycleCloud and secret-access gates pass, reconciles the
scheduler-generated `hpcuser01` public key into CycleCloud, and records idempotency evidence.

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
one identical-input in-place retry only  
**Scale/Scope**: Two persistent Linux VMs, one CycleCloud cluster, one nonprivileged demo user,
and one transient burst node

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Pre-design evaluation | Post-design evaluation |
|---|---|---|
| I. Single Root Composition with Azure Verified Modules | PASS: changes remain in the existing root; no Terraform wrapper module is introduced. | PASS: only a Key Vault role assignment and VM/custom-data inputs change; existing pinned root AVMs remain the resource boundary. |
| II. Terraform Owns the Azure Control Plane | PASS: no Chef recipe creates or mutates Azure resources. | PASS: Azure VM Run Command is an execution transport in the governed workflow; all persistent Azure resource and RBAC state remains Terraform-owned. |
| III. Chef Local Owns Guest Configuration | PASS: cloud-init only installs/verifies/stages and dispatches; Chef owns steady state. | PASS: contracts separate bootstrap states from Chef-owned node outcomes and require zero-update second runs. |
| IV. Security, Networking, and Secret Lifecycle | PASS with researched vendor exception: `azslurm initconfig` only accepts its password through an argument. | PASS: the one invocation is root-only, trace-disabled, nonpersistent, and redacted; all other secret movement uses managed identity and private Key Vault access. |
| V. Test-First Infrastructure | PASS: manifest, state, node-specification, retry, and identity contracts are testable before live deployment. | PASS: quickstart defines targeted static, unit, failure-injection, clean-boot, and idempotency gates. |
| VI. Bounded Capacity and Verified Demonstration | PASS: the existing one-node burst limit is preserved. | PASS: `hpcuser01` reconciliation must complete before any burst-node creation, and acceptance still permits one transient node only. |
| VII. Reproducible and Versioned Dependencies | PASS: all executable inputs require immutable versions and SHA-256 digests. | PASS: Chef 18.11.11 and CycleCloud Slurm 4.0.11 URLs/digests are recorded in the manifest contract; repository bundles are deterministically built and digested. |
| VIII. Operability and Protected Diagnostics | PASS: local status, bounded logs, cleanup, retry state, and secret-free evidence are first-class outputs. | PASS: state and evidence contracts define atomic records, bounded attempts, cleanup proof, and operator-readable failure stages. |

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
│   └── governed-workflow.md
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
│   ├── reconcile-cyclecloud-user.sh
│   └── retrieve-key-vault-secret.py
├── cookbooks/
│   ├── cyclecloud_node/
│   └── slurm_scheduler/
├── policies/
│   ├── cyclecloud.rb
│   └── scheduler.rb
└── test/
    └── integration/

infra/cyclecloud/
├── bootstrap.sh
├── main.bicep
└── modules/

terraform/
├── compute.tf
├── cyclecloud-platform.tf
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
Chef Server, Terraform provisioner, or custom Terraform module.

## Phase 0: Research Outcomes

Research is complete in [research.md](./research.md). It resolves artifact delivery, package
pinning, Slurm release selection, secret retrieval, the `azslurm` credential boundary,
`hpcuser01` reconciliation, dependency dispatch, retry behavior, and idempotency evidence.

## Phase 1: Design Outcomes

- [data-model.md](./data-model.md) defines artifacts, node specifications, dependency gates,
  identity records, attempts, state transitions, and evidence.
- [contracts/](./contracts/) defines machine-validated manifests, role inputs, state, evidence,
  and the governed dispatch sequence.
- [quickstart.md](./quickstart.md) defines the executable validation path from deterministic bundle
  build through clean-boot and second-run proof.

## Complexity Tracking

| Exception | Why Needed | Simpler Alternative Rejected Because |
|---|---|---|
| Root-only transient password argument to `azslurm initconfig` | The release-matched vendor CLI has no password-file, stdin, or environment option. | Hand-writing `autoscale.json` would depend on unsupported internal schema; patching the vendor package would create an unmaintained fork. |
| Azure VM Run Command as scheduler dispatch and public-key handoff | VMs have no public ingress and scheduler convergence must wait for CycleCloud. | Polling from cloud-init races dependencies; SSH from the runner violates the access boundary; standing orchestration software is unnecessary for two nodes. |

## Implementation Sequence

Feature `004-user-friendly-passwords` is an implementation prerequisite. Its generator must
produce or preserve the protected credential set, validate cross-credential uniqueness for newly
generated values, and emit a value-free accepted receipt before feature 005 clean-boot testing.
Feature 005 consumes the existing `cyclecloud-admin-password` Key Vault reference and must not
generate or rotate that credential.

1. Complete and validate feature 004's protected credential-generation prerequisite.
2. Add deterministic role-bundle construction, JSON schema validation, custom-data size gates, and
   pinned package manifest generation.
3. Refactor common bootstrap to verify and install Chef, atomically stage content, lock execution,
   and write environment-ready state without logging protected values.
4. Extend CycleCloud custom data to dispatch first-run then CycleCloud Chef convergence and verify
   cluster import.
5. Extend scheduler custom data and RBAC to stage only; add managed-identity Key Vault REST
   retrieval and protected `azslurm` initialization.
6. Replace `slurmdemo` with `hpcuser01` UID/GID 11200 and add idempotent scheduler SSH-key
   generation.
7. Add the governed dependency check, scheduler dispatch, CycleCloud user reconciliation,
   one-retry limit, second-convergence checks, and evidence capture.
8. Update the governed runbook and execute targeted tests, clean VM rebuilds, one-node burst, and
   final no-change acceptance.
