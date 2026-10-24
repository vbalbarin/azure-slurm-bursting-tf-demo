# Data Model: Automated Chef Bootstrap and Convergence

## Artifact Manifest

An immutable description of every executable or configuration input accepted by one role.

| Field | Type | Rules |
|---|---|---|
| `schemaVersion` | integer | Exactly `1` |
| `role` | enum | `cyclecloud` or `scheduler` |
| `sourceRevision` | string | Full 40-character Git commit |
| `policyName` | string | Role-specific Chef policy name |
| `policyRevision` | string | Immutable policy lock revision |
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

## CycleCloud Application Identity

| Field | Type | Rules |
|---|---|---|
| `name` | string | `hpcadmin` or `hpcuser01` |
| `identityType` | enum | `administrator` or `workload-user` |
| `uid` / `gid` | integer or null | `11200` for `hpcuser01`; null for `hpcadmin` |
| `publicKeyFingerprint` | string or null | SHA-256 fingerprint for `hpcuser01` |
| `clusterAccess` | array | Contains `cross-region-demo` for `hpcuser01` |
| `superuser` | boolean | True only for `hpcadmin` |

`hpcadmin` is an application and scheduler-integration identity, not a required Linux user.
`hpcuser01` is a Linux user on the scheduler and an application identity in CycleCloud, but not a
Linux user on the appliance.

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
result, and for the workload user only its UID/GID and public-key fingerprint.

Evidence must not contain passwords, tokens, private keys, PFX content, secret values, command
lines containing protected values, or reversible secret-derived material.
