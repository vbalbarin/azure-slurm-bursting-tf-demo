# Data Model: Automated Chef Bootstrap and Convergence

## Artifact Manifest

An immutable description of every executable or configuration input accepted by one role.

| Field | Type | Rules |
|---|---|---|
| `schemaVersion` | integer | Exactly `1` |
| `role` | enum | `cyclecloud` or `scheduler` |
| `sourceRevision` | string | Full 40-character Git commit |
| `policyName` | string | Role-specific Chef policy name |
| `policyRevision` | string | 64-character `revision_id` from the reviewed Policyfile lock |
| `policyLockSha256` | string | SHA-256 of the exact role lock file included in the bundle |
| `artifacts` | array | At least policy bundle and Chef package; unique names |
| `artifacts[].kind` | enum | `policy`, `package`, `project`, `tool` |
| `artifacts[].version` | string | Exact version, release, or source revision |
| `artifacts[].uri` | URI or null | Null only for directly delivered custom-data content |
| `artifacts[].sha256` | string | Lowercase 64-character SHA-256 |
| `artifacts[].sizeBytes` | integer | Positive expected size |
| `manifestDigest` | string | SHA-256 of canonical manifest without this field |

**Relationships**: One manifest identifies one policy bundle and is referenced by one or more
convergence attempts only when all attempt inputs are identical.

**Validation**: No mutable URL, branch name, `latest`, secret, or secret-derived value is allowed.
Downloaded size and digest must match before installation or extraction.

## Node Specification

The complete non-secret input for a role and environment.

| Field | Type | Rules |
|---|---|---|
| `schemaVersion` | integer | Exactly `1` |
| `role` | enum | Must match the manifest role |
| `sourceRevision` | string | Must match the manifest source revision |
| `environment` | string | Stable governed environment name |
| `clusterName` | string | Exactly `cross-region-demo` for acceptance |
| `cyclecloudUrl` | URI | Private HTTPS FQDN only |
| `sourceRegion` / `burstRegion` | string | Explicit and different |
| `schedulerPrivateAddress` | IPv4 | Expected scheduler address |
| `burstCidr` | CIDR | Approved compute subnet |
| `slurmUid` / `slurmGid` | integer | Exactly `11100` |
| `mungeUid` / `mungeGid` | integer | Exactly `11101` |
| `hpcUser.name` | string | Exactly `hpcuser01` |
| `hpcUser.uid` / `hpcUser.gid` | integer | Exactly `11200` |
| `hpcUser.home` | path | Exactly `/shared/home/hpcuser01` |
| `secretReferences` | object | Secret names and vault URI only; never values |
| `specificationDigest` | string | SHA-256 of canonical specification without this field |

**Relationships**: The CycleCloud and scheduler specifications share the cluster, endpoint,
regions, Slurm/Munge identities, and `hpcuser01` specification. Each role accepts only its own
validated document.

## Bootstrap Environment

A VM-local immutable release selected by verified digest.

| Field | Type | Rules |
|---|---|---|
| `releasePath` | path | `/opt/slurm-demo/releases/<policy-sha256>` |
| `currentLink` | symlink | Atomically points to one verified release |
| `chefVersion` | string | Exactly `18.11.11` |
| `manifestPath` | path | Root-owned, mode `0444` |
| `nodeSpecificationPath` | path | Root-owned, mode `0444` |
| `wrapperPath` | path | Root-owned, executable, digest-bound |

**Validation**: A release is selectable only after all files validate in a temporary directory.
Existing release contents are never edited in place.

## CycleCloud Identity and RBAC Receipt

A value-free record binding one deployed CycleCloud VM system principal to the exact reviewed
role definition, assignments, and propagated capabilities.

| Field | Type | Rules |
|---|---|---|
| `schemaVersion` | integer | Exactly `1` |
| `sourceRevision` | string | Full approved 40-character Git commit |
| `vmResourceId` | Azure resource ID | Exact approved CycleCloud VM |
| `principalId` | UUID | Derived from `vmResourceId`; caller-supplied substitution prohibited |
| `identityType` | string | Exactly `SystemAssigned` |
| `userAssignedIdentityCount` | integer | Exactly `0` |
| `customRoleDefinitionId` | Azure resource ID | Terraform-owned CycleCloud role |
| `customRoleDefinitionDigest` | string | SHA-256 of the canonical Microsoft permission set |
| `customRoleAssignmentScope` | Azure resource ID | Exact approved burst subscription |
| `keyVaultRoleAssignmentScope` | Azure resource ID | Exact bootstrap vault |
| `lockerIdentityResourceId` | Azure resource ID | Independent Terraform-owned UAMI |
| `lockerRole` | string | Exactly `Storage Blob Data Reader` |
| `lockerRoleAssignmentScope` | Azure resource ID | Exact locker storage account |
| `entraP1Verified` | boolean | Must be `true` for an accepted run |
| `managementAccessVerified` | boolean | Must be `true` before first-run continues |
| `userDelegationVerified` | boolean | Must be `true`; generated SAS is never recorded |
| `secretReadVerified` | boolean | Must be `true`; secret value is never recorded |
| `checkedAt` | timestamp | UTC RFC 3339 |
| `result` | enum | `passed` or `failed` |
| `detailCode` | string | Bounded, non-secret machine-readable code |

**Relationships**: Foundation creates the custom role definition and independent locker identity.
The Bicep stack then creates the VM and its system principal. Post-create Terraform reads that VM,
creates the two orchestrator assignments, and supplies their expected identities to the bounded
guest gate. The receipt is accepted only when live identity shape, assignments, and capabilities
match the approved source and scopes.

**Lifecycle**:

```text
foundation_ready
  -> vm_principal_observed
  -> assignments_applied
  -> propagation_verified
  -> first_run_authorized

replacement_requested
  -> assignments_removed
  -> vm_stack_deleted
```

Any mismatch or timeout transitions to a failed receipt and blocks first-run. VM deletion is
prohibited while assignments for its system principal remain in Terraform state.

## Dependency Gate

| Field | Type | Rules |
|---|---|---|
| `name` | enum | `cyclecloud`, `scheduler-environment`, `secret-access`, `hpc-user` |
| `expectedDigest` | string | Approved receipt or specification digest |
| `observedDigest` | string | Must equal expected |
| `checkedAt` | timestamp | UTC RFC 3339 |
| `result` | enum | `passed` or `failed` |
| `detailCode` | string | Bounded, non-secret machine-readable code |

Scheduler dispatch requires passing `cyclecloud`, `scheduler-environment`, and `secret-access`
gates. Burst-node creation additionally requires the `hpc-user` gate.

## Scheduler Public Identity Receipt

| Field | Type | Rules |
|---|---|---|
| `name` | string | Exactly `hpcuser01` |
| `uid` / `gid` | integer | Exactly `11200` |
| `home` | path | Exactly `/shared/home/hpcuser01` |
| `publicKey` | string | One valid Ed25519 public key; private material prohibited |
| `publicKeyFingerprint` | string | SHA-256 fingerprint derived from `publicKey` |
| `sourceRevision` | string | Full approved source revision |
| `specificationDigest` | string | Approved scheduler specification digest |
| `identityReceiptDigest` | string | SHA-256 of the canonical receipt without this field |

## CycleCloud User-Gate Attestation

| Field | Type | Rules |
|---|---|---|
| `schemaVersion` | integer | Exactly `1` |
| `operator` | string | Non-secret accountable operator identifier |
| `recordedAt` | timestamp | UTC RFC 3339 |
| `userName` | string | Exactly `hpcuser01` |
| `superuser` | boolean | Exactly `false` |
| `nodeAccessEnabled` | boolean | Exactly `true` |
| `uid` | integer | Exactly `11200` |
| `publicKeyFingerprint` | string | Must match the scheduler receipt |
| `sourceRevision` | string | Must match the scheduler receipt |
| `specificationDigest` | string | Must match the scheduler receipt |
| `identityReceiptDigest` | string | Must identify the current scheduler receipt |
| `clusterName` | string | Exactly `cross-region-demo` |
| `clusterPermission` | enum | `node-user` only |
| `applicationPasswordDisposition` | enum | `not-required` or `force-reset-discarded` |
| `result` | enum | `accepted` or `rejected` |

The attestation records only the supported UI outcome and never contains a password, private key,
session token, screenshot with protected data, or undocumented internal CycleCloud payload.
Acceptance is provisional until the first burst node proves UID `11200`, records its observed
primary GID without conflict, and proves key-based and shared-home behavior.

## Convergence Attempt

| Field | Type | Rules |
|---|---|---|
| `attempt` | integer | `1` or `2` for initial convergence; idempotency is a separate check |
| `role` | enum | `cyclecloud` or `scheduler` |
| `manifestDigest` | string | Must remain identical across retry |
| `specificationDigest` | string | Must remain identical across retry |
| `startedAt` / `finishedAt` | timestamp | UTC and monotonic in order |
| `result` | enum | `succeeded`, `failed`, or `interrupted` |
| `updatedResources` | integer or null | Required on successful Chef completion |
| `failureStage` | string or null | Bounded stage identifier, never secret text |

An attempt-2 request with changed digests is a new approved release, not a retry. A second failed
initial attempt transitions the role to `replacement_required`.

## Convergence State

```text
absent
  -> staging
  -> environment_ready

environment_ready
  -> waiting_dependencies       (scheduler only)
  -> converging                 (CycleCloud or authorized scheduler)

converging
  -> converged
  -> failed_retryable           (attempt 1)
  -> replacement_required       (attempt 2)

failed_retryable
  -> converging                 (identical attempt 2 only)

converged
  -> verifying_idempotency
  -> update_authorized          (new governed artifact only)

verifying_idempotency
  -> idempotency_verified       (zero updates)
  -> failed                     (nonzero updates or execution failure)
```

All transitions are serialized by the role lock and written atomically.

## Convergence Evidence

Secret-free proof bound to one role and execution.

Required fields are source revision, manifest and specification digests, Chef and Slurm release
versions, timestamps, attempt/result, state, updated-resource count, dependency receipts, cleanup
result, and for the scheduler workload user its UID/GID and public-key fingerprint. Burst
acceptance evidence separately records UID `11200`, the observed primary GID, key/home checks, and
identity-conflict status.

Evidence must not contain passwords, tokens, private keys, PFX content, secret values, command
lines containing protected values, or reversible secret-derived material.
