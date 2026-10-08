# Data Model: Secure Slurm Bursting Demonstration

This feature stores infrastructure and configuration state rather than application records. The
model below defines the values, relationships, validation rules, and lifecycle states that
Terraform, Chef, the template processor, and acceptance tests must share.

## Demonstration Environment

| Field | Rules |
|---|---|
| `environment_name` | Unique naming prefix; Azure-safe lowercase value |
| `subscription_id` | Existing authorized subscription |
| `tenant_id` | Entra tenant containing operator identities |
| `source_region` | Azure region hosting management and scheduler resources; required and distinct from `burst_region` |
| `burst_region` | Azure region hosting transient compute; required and distinct from `source_region` |
| `resource_group_name` | One feature-owned resource group |
| `cyclecloud_version` | Exactly `8.9.3` for this feature baseline |
| `slurm_project_version` | Discovered from pinned CycleCloud image and recorded before convergence |
| `slurm_version` | Discovered from the selected project template |
| `scheduler_image` | Exact-version AlmaLinux image validated in `source_region` against the scheduler VM size |
| `burst_compute_image` | Independent exact-version AlmaLinux HPC image validated in `burst_region` against the burst VM size |
| `image_compatibility` | Validated common OS family and major release plus role-specific architecture and VM-generation compatibility |
| `cluster_name` | Stable across CycleCloud, scheduler, storage, inventory, and tests |
| `state` | `planned`, `validated`, `provisioned`, `configured`, `verified`, `failed`, `retired` |

**Relationships**: Owns two Network Sites, three Administrative Hosts, one Secret Store, one
Headless Cluster Definition, one Slurm Cluster, and one Audit Evidence Set.

**Transitions**: `planned -> validated -> provisioned -> configured -> verified`. Any gate may move
to `failed`; retry resumes only after the failed gate is corrected. `verified -> retired` is an
operator action.

## Network Site

| Field | Rules |
|---|---|
| `name` | Exactly `vnet-source` or `vnet-burst` |
| `region` | Equals the environment's corresponding `source_region` or `burst_region` |
| `address_space` | Private, non-overlapping CIDR |
| `subnets` | Dedicated workload/access/private-endpoint roles as required |
| `peer_site` | The other Regional Network Site; global peering is bidirectional |
| `private_dns_links` | Required zones linked to each VNET that consumes them |
| `approved_flows` | Least-privilege source, destination, protocol, and port tuples |

## Administrative Host

| Field | Rules |
|---|---|
| `role` | `cyclecloud`, `scheduler`, or `windows_admin`; unique per environment |
| `private_name` | Unique and resolvable from both required sites |
| `private_address` | Assigned from the role subnet; no public IP |
| `image_reference` | Pinned supported image and plan metadata |
| `size` | Regionally available and sufficient for vendor minimums |
| `managed_identity` | Least-privilege identity where Azure data-plane access is required |
| `configuration_policy` | Pinned Chef policy artifact |
| `configuration_state` | `pending`, `converging`, `converged`, `failed` |

## Secret

| Field | Rules |
|---|---|
| `name` | Stable, role-based name without secret material |
| `kind` | Password, SSH private key, certificate, or service credential |
| `owner` | Accountable role |
| `consumers` | Explicit managed identities or operator groups |
| `version` | Immutable Key Vault version identifier |
| `rotation_state` | `current`, `rotation_due`, `retired` |
| `expires_at` | Required where supported |

Secret values never appear in this model, inventory, logs, or nonsensitive outputs.

## Headless Cluster Definition

| Field | Rules |
|---|---|
| `source_path` | Release-matched `slurm.txt` from discovered project |
| `destination_path` | Separate `slurm-headless.txt`; source is never modified |
| `source_digest` | Digest captured before transformation |
| `result_digest` | Digest captured after successful validation |
| `processor_mode` | `python_fallback`; native parser remains unavailable |
| `slurm_uid_gid` | Exactly `11100` |
| `munge_uid_gid` | Exactly `11101` |
| `removed_sections` | Exact README-enumerated set; no extras |
| `validation_state` | `pending`, `valid`, `invalid` |
| `changed` | False when destination already equals validated candidate |

## Slurm Cluster

| Field | Rules |
|---|---|
| `name` | Equals Demonstration Environment `cluster_name` |
| `scheduler_host` | Exactly one Administrative Host with scheduler role |
| `cyclecloud_host` | Exactly one Administrative Host with CycleCloud role |
| `partition` | One acceptance partition |
| `shared_paths` | Exactly `/sched` and `/shared` from scheduler |
| `scheduler_image` | Pinned standard AlmaLinux image assigned only to the persistent scheduler |
| `compute_image` | Independently pinned AlmaLinux HPC image with the same supported OS family and major release as the scheduler |
| `image_compatibility` | `validated` only after role, region, VM-size, architecture, VM generation, family, and major-release checks pass |
| `return_proxy` | Disabled while direct peering is healthy |
| `max_acceptance_nodes` | Exactly one |
| `idle_timeout` | Positive operator-configurable duration |
| `state` | `imported`, `configured`, `off`, `starting`, `ready`, `degraded` |

## Demonstration User

| Field | Rules |
|---|---|
| `username` | Stable configurable nonprivileged name |
| `uid` and `gid` | Same unused numeric value on scheduler and compute nodes |
| `home` | `/shared/home/<username>` |
| `public_key` | Corresponding private key is held only in Key Vault |
| `cluster_access` | Granted only to the demonstration cluster |

## Burst Job

| Field | Rules |
|---|---|
| `job_id` | Assigned by Slurm |
| `user` | Demonstration User |
| `partition` | Acceptance partition |
| `requested_nodes` | Exactly one |
| `state` | `queued`, `configuring`, `running`, `completed`, `failed` |
| `execution_node` | One CycleCloud-created remote node |
| `execution_region` | Equals Demonstration Environment `burst_region` |
| `output_path` | File under demonstration user's shared home |
| `output_evidence` | Contains remote node name |

## Audit Evidence Set

| Field | Rules |
|---|---|
| `validation_results` | Terraform, Chef, Python, and security gate outcomes |
| `plan_reference` | Reviewed saved-plan digest and approval |
| `access_events` | Secret and administrative access events without values |
| `configuration_events` | Convergence and transformation outcomes |
| `cluster_events` | Import, start, node lifecycle, and job evidence |
| `retention_days` | Exactly 90 |

## Cross-entity invariants

1. No Administrative Host, CycleCloud endpoint, or Secret Store has public inbound access.
2. Every Azure resource belongs to the feature resource group and originates from a pinned AVM.
3. Cluster, scheduler, template, project, and user identities are consistent across all entities.
4. A deployment cannot enter `provisioned` without a validated reviewed plan.
5. Guest state cannot enter `converged` without native validation and second-run idempotency.
6. A headless definition cannot become `valid` if the source combination fails compatibility or
   if the last valid destination would be lost on failure.
7. The scheduler and persistent administration resources are in `source_region`; every acceptance
   compute node is in the distinct `burst_region`.
8. Scheduler and burst-compute image URNs are distinct, exact-version values assigned only to
   their intended roles and validated against their respective regions and VM sizes.
