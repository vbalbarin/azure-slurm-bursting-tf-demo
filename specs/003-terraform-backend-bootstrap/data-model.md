# Data Model: Terraform State Backend Bootstrap

This feature manages infrastructure state and evidence rather than application records. The model
defines the values, ownership boundaries, validation rules, and lifecycle transitions shared by
the bootstrap root, dependent roots, readiness checks, and operator approvals.

## Bootstrap Configuration

| Field | Rules |
|---|---|
| `subscription_id` | Approved Azure subscription UUID |
| `tenant_id` | Entra tenant UUID containing approved principals |
| `location` | Approved Azure region with a defined short code |
| `workload_name` | Lowercase ALZ workload token; length constrained by generated names |
| `environment_name` | Lowercase environment token; used as the state-key prefix |
| `instance` | Integer 0–99, formatted as two digits |
| `uniqueness_code` | Four to six lowercase alphanumeric characters; non-secret and stable outside state |
| `ownership_mode` | `managed` or `existing`; defaults to `managed` |
| `network_mode` | `restricted_public` or `private`; defaults to `restricted_public` |
| `operator_group_object_id` | Existing Entra security-group object ID; required in managed mode |
| `workload_identity_object_id` | Optional approved service-principal object ID |
| `allowed_public_ipv4_cidrs` | One or more public IPv4 CIDRs in restricted-public mode; empty otherwise |
| `private_endpoint_subnet_id` | Existing reachable subnet resource ID; required only in private managed mode |
| `private_dns_zone_id` | Existing `privatelink.blob.core.windows.net` zone ID; required only in private managed mode |
| `existing_backend` | Explicit account, container, resource IDs, and network mode; required only in existing mode |
| `tags` | Approved non-secret governance tags |

**Relationships**: Selects one Naming Set, one Network Profile, one ownership path, one operator
group, and zero or one workload identity. Produces one Backend Coordinates record.

## Naming Set

| Field | Rules |
|---|---|
| `region_code` | Validated mapping for `location` |
| `instance_code` | Two digits |
| `resource_group_name` | `rg-<workload>-<environment>-<region-code>-<instance>` |
| `storage_account_name` | `st<workload-token><environment-token><region-code><instance><uniqueness>`; lowercase alphanumeric; 3–24 chars |
| `container_name` | Exactly `tfstate` |
| `private_endpoint_name` | ALZ-style resource type, workload, environment, region, and instance components |

Names are deterministic from configuration and remain reconstructable without Terraform state.

## Backend Resource Set

| Field | Rules |
|---|---|
| `ownership_mode` | `managed` resources have lifecycle ownership; `existing` resources never do |
| `resource_group_id` | Created in managed mode or supplied/read in existing mode |
| `storage_account_id` | Created in managed mode or supplied/read in existing mode |
| `container_id` | Private Blob container; no anonymous access |
| `private_endpoint_id` | Present only in private managed mode |
| `public_network_access` | Enabled only for restricted-public mode |
| `shared_key_access` | Always disabled for managed mode |
| `minimum_tls` | TLS 1.2 or later |
| `versioning` | Enabled in managed mode |
| `soft_delete_days` | Seven in managed mode |
| `deletion_lock` | `CanNotDelete` in managed ordinary operation |
| `lifecycle_state` | See Backend Lifecycle |

## Network Profile

| Field | Rules |
|---|---|
| `mode` | `restricted_public` or `private` |
| `approved_sources` | Explicit public IPv4 CIDRs for restricted-public mode |
| `subnet_id` | Existing subnet for private mode |
| `private_dns_zone_id` | Existing Blob private DNS zone for private mode |
| `expected_dns_result` | Public endpoint in restricted-public mode; private address in private mode |
| `fallback_allowed` | Always false |

## Access Assignment

| Field | Rules |
|---|---|
| `principal_id` | Operator group or optional workload identity object ID |
| `principal_type` | `Group` or `ServicePrincipal` |
| `role` | Exactly `Storage Blob Data Contributor` |
| `scope` | Exactly the `tfstate` container |
| `ownership` | Created only in managed mode |
| `propagation_state` | `pending`, `effective`, or `failed` |

Direct user assignments are absent unless separately approved outside the default contract.

## Backend Coordinates

| Field | Rules |
|---|---|
| `schema_version` | Contract version |
| `ownership_mode` | `managed` or `existing` |
| `subscription_id`, `tenant_id` | Equal approved account context |
| `resource_group_name` | Backend resource group |
| `storage_account_name` | Azure-valid account name |
| `container_name` | Exactly `tfstate` unless existing mode explicitly approves another private container |
| `network_mode` | Equal selected Network Profile |
| `bootstrap_state_key` | `<environment>/bootstrap.tfstate` |
| `main_state_key` | `<environment>/main.tfstate` |
| `capacity_probe_state_key` | `<environment>/capacity-probe.tfstate` |
| `resource_ids` | Non-secret IDs for managed or validated existing resources |

## State Namespace

| Field | Rules |
|---|---|
| `kind` | `bootstrap`, `main`, or `capacity_probe` |
| `key` | Exact environment-scoped key from Backend Coordinates |
| `storage_state` | `absent`, `local`, `migrating`, `remote`, `empty`, or `failed` |
| `lock_state` | `unlocked`, `locked`, `conflict`, or `unknown` |
| `managed_resource_count` | Zero or positive; must be zero before backend removal |
| `digest` | SHA-256 of protected state artifact where evidence may safely record only the digest |

State content is sensitive and never copied into the evidence model.

## Backend Readiness Evidence

| Field | Rules |
|---|---|
| `schema_version` | Contract version |
| `source_commit` | Exact Git commit being authorized |
| `assessed_at` | UTC timestamp; valid for at most one hour |
| `status` | `ready` or `failed` |
| `failure_class` | `none`, `missing_backend`, `missing_container`, `authentication_failed`, `authorization_failed`, `dns_failed`, `network_failed`, `state_key_collision`, `lock_failed`, or `configuration_mismatch` |
| `identity` | Non-secret tenant, principal ID, and principal type |
| `execution_context` | Non-secret network mode, runner-context digest, observed source or private-network digest, resolved Blob addresses, and observation time |
| `coordinates` | Exact Backend Coordinates subset |
| `checks` | Account, container, DNS, endpoint mode, authorization, key separation, migration, and lock outcomes |

**Validity**: Evidence authorizes dependent planning only when status is `ready`, source commit,
environment, account context, coordinates, identity scope, execution-context digest, and age all
match.

## Readiness Assertions

| Field | Rules |
|---|---|
| `schema_version` | Contract version |
| `source_commit` | Exact Git commit being assessed |
| `coordinates_digest` | SHA-256 of canonical Backend Coordinates |
| `assessment_started_at`, `assessment_completed_at` | UTC timestamps within the one-hour validity window |
| `execution_context` | Exact non-secret context also embedded in final readiness evidence |
| `checks` | Stable command ID, observation time, exit code, status, non-secret observed value, and optional detail for every readiness check |

Raw command output is not retained. Assertions contain only bounded, non-secret values required for
classification. The runner-context digest is calculated from canonical network-mode-specific
context and changes when the observed public source, private-network context, or resolved Blob
addresses change.

The canonical JSON digest is stored in an adjacent `.sha256` sidecar. It is not embedded in the
document because a document cannot contain the SHA-256 digest of its own canonical bytes.

## Migration Acceptance Evidence

| Field | Rules |
|---|---|
| `schema_version` | Contract version |
| `source_commit` | Exact Git commit under acceptance |
| `observed_at` | UTC completion timestamp |
| `coordinates_digest` | SHA-256 of canonical Backend Coordinates |
| `local_state` | Protected path class, mode, lineage, resource count, retained-until-verified result, and content-free digest |
| `remote_state` | Pull result, lineage, resource count, and exact bootstrap key |
| `lineage_matches` | True only when protected local and remote lineage are equal |
| `resource_count_matches` | True only when protected local and remote resource counts are equal |
| `no_change_plan` | Exit status and `no_changes` result without plan content |
| `stale_plan_rejection` | Exit status and rejection result without raw diagnostic output |
| `lock_conflict` | First-operation lock acquisition/release and second-operation rejection results |
| `namespaces` | Exact bootstrap, main, and capacity-probe keys plus pairwise-isolation result |
| `verification_status` | `passed` or `failed` |

The contract contains no state, plan, raw command output, credential, or protected input. Python
tests validate this document only and never execute migration or control-plane commands.

## Live Acceptance Evidence

| Field | Rules |
|---|---|
| `schema_version` | Contract version |
| `source_commit` | Exact Git commit under acceptance |
| `run_id` | New evidence-run identifier; never the stopped run |
| `started_at`, `completed_at` | UTC acceptance interval |
| `bootstrap_elapsed_seconds` | Excludes separately recorded role-propagation delay; maximum 1200 |
| `role_propagation_delay_seconds` | Separately measured nonnegative duration |
| `replacement_operator` | Non-secret tenant, principal ID/type, authenticated start, completion, and elapsed seconds; maximum 900 |
| `namespace_access` | Initialization, read, and lock results for bootstrap, main, and capacity-probe |
| `reverse_migration` | Mode-`0600` local state, lineage/resource-count verification, and digest match |
| `unlock` | Exact unlock-only plan digest, approval reference, stale-plan result, and applied-plan digest match |
| `destroy` | Separate destroy-plan digest, approval reference, stale-plan result, and applied-plan digest match |
| `backend_absence` | Account/container absence result after approved managed cleanup |
| `secret_hygiene` | Git/evidence inspection result and zero prohibited-artifact count |
| `status` | `passed` only when every required result passes |

The contract is a secret-free summary of direct operator execution. It contains digests and bounded
results only, never state, plans, credentials, protected inputs, or raw command output. Python tests
validate this document only and never invoke Terraform, Azure CLI, or control-plane operations.

## Backend Lifecycle Evidence

| Field | Rules |
|---|---|
| `schema_version` | Contract version |
| `source_commit` | Exact Git commit being authorized |
| `assessed_at` | UTC timestamp |
| `status` | `ready` or `blocked` |
| `failure_class` | Stable removal/recovery classification |
| `ownership_mode` | `managed` or `existing`; existing is always blocked for backend removal |
| `action` | `migrate_local`, `unlock`, or `destroy` |
| `coordinates` | Exact Backend Coordinates subset |
| `namespaces` | Main and capacity-probe presence and managed-resource counts |
| `bootstrap_state` | Local/remote/missing location, digest, and reverse-migration status |
| `approval_reference` | Accountable external review/change reference |

## Plan Approval

| Field | Rules |
|---|---|
| `action` | `create`, `unlock`, or `destroy` |
| `plan_digest` | SHA-256 of the already-generated exact applicable plan |
| `source_commit` | Exact source commit used to generate the plan |
| `input_digest` | SHA-256 of the protected input set used to generate the plan |
| `approval_reference` | Accountable external review/change reference |
| `approved_at` | UTC timestamp |

Plan approval is external to Terraform plan inputs. The saved plan is generated first, then its
digest is recorded and approved, and the approval record is verified immediately before manual
application. Terraform independently rejects a plan whose state snapshot has become stale.

## Migration Approval

| Field | Rules |
|---|---|
| `action` | `migrate_remote` or `migrate_local` |
| `state_digest` | SHA-256 of protected source state before migration |
| `readiness_digest` | Required before remote migration |
| `approval_reference` | Accountable external review/change reference |
| `approved_at` | UTC timestamp |

Migration approval has no plan digest because `terraform init -migrate-state` is a state operation,
not a saved Terraform plan.

## Backend Lifecycle

### Managed mode

```text
uninitialized
  -> local_planned
  -> local_applied
  -> pre_migration_ready
  -> migrating_remote
  -> remote_verified
  -> operational
  -> dependents_empty
  -> migrating_local
  -> local_verified
  -> unlock_planned
  -> unlocked
  -> destroy_planned
  -> removed
```

Any failed gate transitions to `failed`. Resume is allowed only from the last verified state with
matching configuration, state digest, and approval context.

### Existing mode

```text
uninitialized
  -> coordinates_validated
  -> pre_migration_ready
  -> migrating_remote
  -> remote_verified
  -> operational
```

Existing mode has no unlock or removal transition because organizational resources remain outside
feature ownership. Ending use removes only project state after the managed demo and probe resources
are empty and separately approved.
