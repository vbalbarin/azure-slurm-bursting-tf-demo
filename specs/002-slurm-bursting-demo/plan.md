# Implementation Plan: Secure Slurm Bursting Demonstration

**Branch**: `main` | **Date**: 2026-10-08 |
**Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/002-slurm-bursting-demo/spec.md`

## Summary

Build a cross-region Azure demonstration with a source-region management VNET and a burst-region
compute VNET connected by bidirectional global peering. The source region hosts private CycleCloud
8.9.3, an external Slurm scheduler on a pinned AlmaLinux image compatible with its general-purpose
VM size, a Windows administration jump host, Standard Bastion with a public service endpoint,
private Key Vault access, private DNS, and 90-day audit retention. Bastion reaches only the
Windows host over RDP; the Windows access subnet
reaches the Linux management subnet over SSH and the private CycleCloud application over HTTPS.
The separately selected burst region hosts transient compute on an independently
pinned AlmaLinux HPC image compatible with its selected compute size. Terraform calls pinned Azure
Verified Modules directly for every surrounding Azure resource. A source-controlled Bicep
deployment stack owns only the released CycleCloud Marketplace VM because its required image data
disk cannot be represented by the approved Terraform VM module. Terraform also owns separate
CycleCloud control and locker identities, a dedicated compute resource group, and a private locker
storage account/container. Secure cloud-init retrieves generated administrator and TLS material
from Key Vault, initializes the application and protected CLI, and creates the managed-identity
Azure provider account before Chef Local converges the CycleCloud and scheduler guests. A narrowly
scoped Python processor discovers the installed Slurm project,
transforms its cluster template into a headless definition with guarded atomic writes, and fails
closed when the pinned product, regional, or role-specific image combination is incompatible. The
acceptance path submits one job in the source region and proves that one transient compute node
executed it in the burst region. Before main-environment approval, the operator validates total and
VM-family quota, exact zonal eligibility, and a controlled one-node allocation probe, and can
compare an ordered set of approved alternate region/zone candidates without automatic
substitution.
Each region has a Standard NAT Gateway because Azure NAT Gateway associations are regional and
cannot provide outbound access to a peered VNET. The source gateway serves the access and
management subnets, and the burst gateway serves the compute subnet. This duplication keeps the
demonstration self-contained; a production landing zone would normally consume governed
hub/connectivity egress unless workload or regional requirements justified separate gateways.
The Bastion public IP is a separate root-owned AVM object passed into the Bastion module. Its
configuration includes Azure's reserved service IP tag, avoiding replacement drift while
preserving explicit dependency-ordered destruction. Immediately after foundation apply, an
unchanged-plan gate blocks all secret writes and appliance deployment if Azure normalization or
any other refresh produces a change.

## Technical Context

**Language/Version**: Terraform >= 1.9 and < 2.0; HCL; Chef Infra Client pinned during
implementation; Python 3 from the pinned CycleCloud image

**Primary Dependencies**: AzureRM and AzAPI providers; direct pinned calls to Azure Verified
Modules; Azure CLI and Bicep CLI for the VM-only deployment stack; CycleCloud 8.9.3; independently
pinned compatible scheduler and burst-compute AlmaLinux images; the Slurm project installed with
the pinned CycleCloud image; Chef Local; CycleCloud CLI and `azslurm`; pytest and Bandit for the
fallback processor

**Storage**: Key Vault for credentials and generated private TLS material; a private
managed-identity-authenticated CycleCloud locker account/container; scheduler-hosted NFS for
`/sched` and `/shared`; Log Analytics with 90-day retention; local configuration files managed by
cloud-init and Chef

**Testing**: `terraform fmt -check`, `terraform validate`, TFLint, Checkov, reviewed Terraform
plan; Cookstyle, Chef unit tests, Test Kitchen and InSpec with a second-converge no-change gate;
pytest and Bandit; quota and zonal-restriction fixtures; capacity-probe success, allocation
failure, timeout, and cleanup-failure tests; end-to-end Slurm burst-job validation

**Target Platform**: Two distinct operator-selected Azure regions connected by global VNET
peering; Azure CycleCloud 8.9.3 Marketplace VM; a supported source-region AlmaLinux scheduler
image; a separately pinned burst-region AlmaLinux HPC compute image; supported Windows Server
administration VM

**Project Type**: Infrastructure as code plus guest configuration management and one guarded
configuration-file processor

**Performance Goals**: Complete provisioning in at most 90 minutes; private UI inspection in at
most 5 minutes; one-node burst job output in at most 15 minutes under normal capacity

**Constraints**: AVM-only Terraform resources, including temporary capacity-probe resources; one
narrow CycleCloud VM-only Bicep deployment-stack exception; no direct Azure Terraform resource
blocks or custom Terraform modules; no public VM or CycleCloud ingress; Key Vault may expose only
the approved runner `/32` during initial secret creation and, when required by active policy, may
carry `SecurityControl=Ignore` on only the Key Vault under explicit plan approval; the `/32` and
tag must be removed together when returning to private-only before acceptance; explicit distinct
source and burst regions
and an explicit burst zone with no automatic substitution; operator-approved alternate candidates
are assessed in their supplied order but are not discovered or deployed automatically; latest
release supported by both regions selected during planning and pinned; one compute node for the
capacity probe and acceptance; no HA, DR, automatic region failover, or scale testing; scheduler
and burst-compute images must be explicit, exact-version inputs validated by role, region, zone,
VM size, and compatible operating-system family/major release; configuration must be
non-interactive and idempotent; secrets must not appear in outputs or logs

**Scale/Scope**: One resource group spanning two regions, two VNETs, bidirectional global peering,
two regional NAT Gateways, dedicated management and burst-workload subnets, one source-region
CycleCloud VM with a control identity, one dedicated compute resource group, one locker identity
and private locker storage account/container, one source-region scheduler VM, one source-region
Windows VM, one source-region Bastion host, one Key Vault, one Log Analytics workspace, one
headless cluster, one demonstration user, and at most one burst-region node during acceptance

## Constitution Check

*GATE: Passed before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Design evidence | Status |
|---|---|---|
| Compliance-preserving legacy operation | New isolated demonstration scope; no mutation or deletion of retained legacy resources; plan review blocks replacement and destruction. | PASS |
| Declarative infrastructure and managed node configuration | Terraform owns all surrounding Azure resources. The approved Bicep stack owns only the CycleCloud Marketplace VM. Chef Local owns guest state. Python is limited to one node-consumed template and performs no Azure operations. | PASS |
| Azure Verified Modules and CycleCloud appliance exception | Every Terraform resource is created through a pinned published AVM called directly from the root. The only non-AVM resource is the constitution-authorized VM-only Bicep stack. | PASS |
| Security without exception | Bastion Standard is the sole interactive public ingress and reaches only the private Windows jump host over RDP; VMs have no public IPs; Bastion has no direct SSH path to Linux hosts; Key Vault is private after provisioning; two regional NAT Gateways provide explicit VM outbound access; Entra ID/RBAC, least privilege, certificate trust, and auditable operations are explicit. | PASS |
| Reliable, idempotent, validated change | Terraform, Chef, and Python each have syntax, security, idempotency, failure, and review gates. The exact plan is applied only after validation, then an immediate unchanged-plan gate blocks downstream work on drift. | PASS |
| Scope constraints | Two-region placement and advisory assessment of operator-approved candidates demonstrate placement flexibility without HA, DR, automatic failover, or multi-node scaling. | PASS |

### Pre-design gate

Research confirmed published AVMs cover every surrounding resource type. The CycleCloud 8.9.3
Marketplace image declares an embedded data disk at LUN 0 that the approved Terraform VM module
cannot express in its initial VM request, so the constitution-authorized Bicep stack owns that VM
alone. CycleCloud 8.9.3 is the pinned current GA release. Public documentation does not certify every 8.9.3, Slurm project, and
AlmaLinux image combination, so deployment includes a fail-closed compatibility preflight that
discovers the installed project/template and independently validates the scheduler image against
the source region and scheduler VM size and the burst-compute image against the burst region and
compute VM size. It also validates that both images provide a compatible AlmaLinux family and major
release before transformation. The preflight validates both explicit regions, global peering support, images, SKUs, total
regional and VM-family quota, zonal restrictions, and point-in-time burst allocation without
choosing a substitute region, zone, image, or SKU. The capacity probe is a separately reviewed,
time-bounded Terraform deployment using a pinned compute AVM; shell and Python orchestration do not
create Azure resources. Probe cleanup is verified and blocks main-environment approval when
incomplete. These are operational gates, not unresolved requirements.

### Post-design gate

The data model, contracts, and quickstart retain the separation between Terraform-owned
infrastructure, the CycleCloud VM-only Bicep stack, Chef-managed guest configuration, and the
permitted Python file processor. The Key Vault provisioning exception is bounded to one approved
runner `/32`, one resource-scoped exclusion tag under explicit approval, and a mandatory hardening
plan that removes both. No artifact introduces direct Terraform resources,
custom Terraform modules, public management ingress in the accepted environment, unvalidated
deployment, HA, DR, or additional scale. All gates remain PASS.

## Project Structure

### Documentation (this feature)

```text
specs/002-slurm-bursting-demo/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── infrastructure.md
│   ├── node-configuration.md
│   └── headless-template-processor.md
└── tasks.md
```

### Source Code (repository root)

```text
terraform/
├── versions.tf
├── providers.tf
├── variables.tf
├── locals.tf
├── network.tf
├── security.tf
├── compute.tf
├── monitoring.tf
├── outputs.tf
└── environments/

infra/
└── cyclecloud/
    └── main.bicep─ environments/
    └── demo.tfvars.example

chef/
├── cookbooks/
│   ├── cyclecloud_node/
│   │   ├── attributes/
│   │   ├── recipes/
│   │   ├── templates/
│   │   └── test/
│   └── slurm_scheduler/
│       ├── attributes/
│       ├── recipes/
│       ├── templates/
│       └── test/
├── policyfiles/
├── test/
│   └── integration/
└── kitchen.yml

tools/
└── headless_template/
    ├── pyproject.toml
    ├── src/
    │   └── headless_template/
    └── tests/

tests/
├── terraform/
├── policy/
└── end-to-end/
```

**Structure Decision**: Keep three explicit ownership boundaries. Root Terraform files directly
compose pinned AVM calls and contain no reusable custom modules. Chef cookbooks converge guest
state. The Python package has one configuration-file transformation responsibility and no Azure
SDK dependency. Test directories mirror those boundaries and add one end-to-end acceptance path.

## Complexity Tracking

No constitution violations require justification.
