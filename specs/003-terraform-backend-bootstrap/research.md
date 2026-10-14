# Phase 0 Research: Terraform State Backend Bootstrap

## Azure resource composition

**Decision**: In managed mode, call these published Azure Verified Modules directly from the
bootstrap root:

| Capability | AVM source | Pinned version |
|---|---|---|
| Resource group | `Azure/avm-res-resources-resourcegroup/azurerm` | `0.4.0` |
| Storage account, container, network rules, role assignments, private endpoint, and lock | `Azure/avm-res-storage-storageaccount/azurerm` | `0.10.0` |

Use the storage module's embedded `private_endpoints` input with a pre-existing subnet and private
DNS zone. Do not add the standalone private-endpoint module or create a network/DNS topology in
this bounded feature.

**Rationale**: The storage module exposes every managed capability required by the specification,
including a private container, default-deny network rules, public IP rules, private endpoint zone
groups, role assignments, OAuth defaults, shared-key disablement, encryption settings, and a
`CanNotDelete` lock. Direct root calls satisfy the AVM-only constitution and keep the topology
minimal. Private mode already assumes a reachable private network path.

**Alternatives considered**: Direct Azure resources and local wrapper modules violate the
constitution. A standalone private-endpoint AVM adds an unnecessary dependency. Creating a VNET and
DNS topology would exceed backend bootstrap scope.

**Sources**:

- <https://registry.terraform.io/modules/Azure/avm-res-resources-resourcegroup/azurerm/0.4.0>
- <https://registry.terraform.io/modules/Azure/avm-res-storage-storageaccount/azurerm/0.10.0>
- <https://github.com/Azure/terraform-azurerm-avm-res-storage-storageaccount>

## Terraform and provider baseline

**Decision**: Require Terraform >= 1.10 and < 2.0 only in the bootstrap root, while retaining the
existing roots' >= 1.9 and < 2.0 declarations. Pin AzAPI 2.12.0 in the root; accept the AVMs'
transitive compatible ModTM and Random provider constraints through the lock file. Continue using
the development container's Terraform 1.16.5 and Azure CLI 2.91.0.

**Rationale**: Storage AVM 0.10.0 declares Terraform >= 1.10 and AzAPI ~> 2.11. The current toolchain
already exceeds the minimum, and AzAPI 2.12.0 satisfies both selected AVMs. Isolating the higher
minimum avoids an unrelated compatibility change to existing roots.

**Alternatives considered**: Pinning an older storage AVM only to retain a 1.9 bootstrap floor was
rejected because the actual environment is newer and the current module carries the researched
security and interface baseline. Raising every root's minimum was rejected as unrelated.

**Sources**:

- <https://raw.githubusercontent.com/Azure/terraform-azurerm-avm-res-storage-storageaccount/v0.10.0/terraform.tf>
- <https://raw.githubusercontent.com/Azure/terraform-azurerm-avm-res-resources-resourcegroup/v0.4.0/terraform.tf>

## Backend authentication and authorization

**Decision**: Configure the `azurerm` backend for Microsoft Entra authentication. Interactive
operators use Azure CLI credentials with `use_azuread_auth=true` and `use_cli=true`. Automation uses
an approved federated workload identity. Assign `Storage Blob Data Contributor` at the `tfstate`
container scope to the approved operator group and optional workload identity.

**Rationale**: HashiCorp and Microsoft recommend Entra authentication over access keys or SAS.
Container scope supplies the state read, write, delete, and lease operations required by all three
keys while avoiding account-wide data access. Subscription Owner or Contributor remains distinct
from Blob data-plane authorization.

**Alternatives considered**: Account keys, SAS, access-key lookup, and committed backend credentials
were rejected. Account-scope Blob roles were rejected because container scope is sufficient.
Direct user assignment remains an explicitly approved exception, not a default.

**Sources**:

- <https://developer.hashicorp.com/terraform/language/backend/azurerm>
- <https://learn.microsoft.com/azure/developer/terraform/store-state-in-azure-storage>
- <https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/storage>

## Bootstrap state lifecycle

**Decision**: Mount a separate named Docker volume at `/state` with mode `0700`; keep initial state
under `/state/terraform-backend/<environment>/`. The bootstrap root contains no active backend block
until an ignored copy of `backend.azurerm.tf.example` is installed after readiness. Migrate with
`terraform init -migrate-state`, retain a mode-`0600` local copy and digest until a remote no-change
plan verifies migration, then securely remove the local copy. Before managed-backend removal,
restore the protected local copy with reverse `-migrate-state`, verify it, and remove the override
before unlocking or destroying the backend.

**Rationale**: The backend cannot store the state that creates it until it exists. Terraform
documents `-migrate-state` as the copy-preserving backend transition; `-reconfigure` explicitly does
not migrate state. A separate state volume survives container rebuilds but remains segregated from
secret-free evidence. The reverse migration prevents deletion of the storage account that contains
the active state tracking its deletion.

**Alternatives considered**: Permanent workspace-local state is not durable. The evidence volume
cannot contain potentially sensitive Terraform state. Permanent local state conflicts with the
clarified recovery requirement. HCP Terraform or a second organizational backend would add an
unapproved dependency.

**Sources**:

- <https://developer.hashicorp.com/terraform/cli/commands/init>
- <https://developer.hashicorp.com/terraform/language/backend/configuration>

## Network access

**Decision**: Default to restricted-public mode with public network access enabled, network default
action `Deny`, and only explicit approved public IPv4 CIDRs in `ip_rules`. Private mode disables
public network access and creates a Blob private endpoint using operator-supplied existing subnet
and `privatelink.blob.core.windows.net` private DNS zone resource IDs. Never auto-detect or silently
add the caller address.

**Rationale**: Restricted-public mode supports a customer laptop without presupposing VPN,
ExpressRoute, private DNS forwarding, or a bootstrap VNET. Explicit input keeps the plan reviewable
and fails closed when the source address changes. Private mode provides the stronger governed path
where networking already exists.

**Alternatives considered**: Unrestricted public access violates the constitution. Automatic
caller-IP discovery would hide a mutable network authorization. Creating a VNET/DNS platform is
outside scope. Storage service endpoints were rejected because they do not satisfy the clarified
private-endpoint mode.

**Sources**:

- <https://learn.microsoft.com/azure/storage/common/storage-network-security>
- <https://learn.microsoft.com/azure/private-link/private-endpoint-dns>

## Storage protection and recovery

**Decision**: Disable shared-key authorization and anonymous access, require TLS 1.2 or later and
HTTPS, enable infrastructure encryption where supported, enable blob versioning plus blob and
container soft delete for seven days, and apply a `CanNotDelete` storage-account lock in managed
mode. Removal is a two-plan process: an explicitly approved unlock change followed by a separately
reviewed destroy plan after dependent-state emptiness and reverse migration are verified.

**Rationale**: State may contain sensitive values and is critical to cleanup and recovery. Soft
delete/versioning provide bounded accidental-deletion recovery without introducing geo-DR. The
Azure lock is the hard backstop; workflow gates supply the dependency-aware checks Azure does not
natively provide.

**Alternatives considered**: Read-only locks block legitimate state writes. Geo-redundancy and
long-term retention exceed the demo's HA/DR scope. A single unlock-and-destroy action weakens review
and recovery.

**Sources**:

- <https://learn.microsoft.com/azure/storage/blobs/versioning-overview>
- <https://learn.microsoft.com/azure/storage/blobs/soft-delete-blob-overview>
- <https://learn.microsoft.com/azure/azure-resource-manager/management/lock-resources>

## Naming contract

**Decision**: Use ALZ-style structured names. Resource-group names use
`rg-<workload>-<environment>-<region-code>-<instance>`. Storage names use
`st<workload-token><environment-token><region-code><instance><uniqueness>`, normalized to lowercase
alphanumeric and limited to 24 characters. The operator supplies a stable four-to-six-character
lowercase alphanumeric uniqueness code. The container is fixed as `tfstate`; keys carry
environment separation.

**Rationale**: The structure is readable where Azure permits separators and deterministic after
state loss. Explicit uniqueness avoids deriving names from tenant/subscription identifiers or a
random resource stored only in bootstrap state.

**Alternatives considered**: Random suffixes hinder recovery after state loss. Subscription/tenant
hashes create unwanted organizational correlation. Separate per-environment containers complicate
RBAC without adding value.

**Sources**:

- <https://learn.microsoft.com/rest/api/storageservices/naming-and-referencing-containers--blobs--and-metadata>
- <https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming>

## Managed and existing ownership modes

**Decision**: `managed` is the default and creates/owns all backend resources. `existing` requires
explicit coordinates, creates no module instances or role assignments, validates applicable
security and connectivity, and may create only this project's three state blobs through normal
backend use. It never imports, mutates, locks, unlocks, or destroys organizational resources.

**Rationale**: Customers can comply with central backend governance without transferring lifecycle
ownership. Infrastructure validation remains read-only; normal state use still requires Blob Data
Contributor because Terraform must write and lease project state.

**Alternatives considered**: Importing existing resources creates ownership ambiguity. Requiring a
new backend conflicts with some customer governance. Reader-only access cannot support ordinary
Terraform state writes.

**Sources**:

- <https://developer.hashicorp.com/terraform/language/backend/azurerm>
- <https://learn.microsoft.com/azure/storage/blobs/assign-azure-role-data-access>

## Readiness, evidence, and dependent-plan gates

**Decision**: Use native Terraform locals, checks, preconditions, and outputs in the bootstrap root
to classify readiness and emit a value matching `backend-readiness.schema.json`. Operators run
documented Azure CLI, DNS, HTTP, state-pull, no-change-plan, and lock-conflict commands directly and
record their non-secret results in a protected readiness-assertions input matching
`backend-readiness-assertions.schema.json`. Every result records a stable command ID, observation
time, exit code, non-secret observed value, coordinate digest, and execution-context digest.
The context contains network mode, observed public source IPv4 or private-network context digest,
resolved Blob endpoint addresses, and observation time, but no hostname, username, or credential.
Preliminary evidence
covers account context, coordinate shape, DNS, endpoint mode, container access, expected role
assignments, and state-key separation. After migration, direct Terraform state and plan commands
prove remote data-plane access and locking before final evidence may become `ready`. Evidence is
valid only for the same source commit, environment, coordinates, identity scope, execution-context
digest, and a one-hour window. Main and probe roots consume the JSON plus the current protected
execution-context digest through native Terraform checks and fail before resource planning when it
is absent, stale, failed, or mismatched. A SHA-256 sidecar authenticates the canonical JSON without
introducing a self-referential digest field.

**Rationale**: Terraform remains the sole implementation and classification mechanism while direct
operator commands perform only explicit inspection, migration, and native backend operations. This
meets the constitution without inventing a general-purpose Bash/Python exception. Digest-bound
evidence prevents a result from another backend or source revision from authorizing plans.

**Alternatives considered**: A custom Bash/Python readiness helper conflicts with the constitution,
even if read-only. A script that runs apply also violates the constitution. Relying only on raw
backend error text lacks stable classifications. Permanent readiness validity would ignore later
RBAC, DNS, network, or source changes.

**Sources**:

- <https://developer.hashicorp.com/terraform/language/checks>
- <https://learn.microsoft.com/cli/azure/storage/container>

## Validation and teardown

**Decision**: Use native Terraform tests and policy tests for deterministic configuration and
readiness/lifecycle classification coverage, JSON Schema contract tests, and a live integration
test for local→remote→local migration, lock conflict, second no-change plan, digest mismatch,
stale-plan rejection, and managed teardown. Teardown first proves main and probe state contain no
managed resources, migrates bootstrap state local, generates and externally approves an unlock
plan, verifies its digest immediately before apply, then repeats that separate sequence for the
destroy plan. Existing mode has no teardown action.

**Rationale**: Azure has no native rule that blocks storage deletion based on the semantic contents
of other state blobs. Combining workflow checks, a resource lock, exact plans, and live migration
testing supplies the required fail-closed behavior.

**Alternatives considered**: Blob existence alone is insufficient because an empty Terraform state
blob may remain. One-step forced deletion was rejected. Azure Policy for this demo-specific
dependency would add disproportionate scope.

**Sources**:

- <https://developer.hashicorp.com/terraform/language/tests>
- <https://developer.hashicorp.com/terraform/cli/commands/state/pull>
- <https://developer.hashicorp.com/terraform/cli/commands/show>
