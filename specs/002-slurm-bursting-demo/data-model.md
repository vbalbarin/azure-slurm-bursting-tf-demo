# Data Model: Secure Slurm Bursting Demonstration

This feature stores infrastructure and configuration state rather than application records. The
model below defines the values, relationships, validation rules, and lifecycle states that
Terraform, Chef, the template processor, and acceptance tests must share.

## Demonstration Environment

| Field | Rules |
|---|---|
| `environment_name` | Unique naming prefix; Azure-safe lowercase value |
| `backend_environment_name` | Governed backend state-key prefix; may differ from the workload naming prefix |
| `subscription_id` | Existing authorized subscription |
| `tenant_id` | Entra tenant containing operator identities |
| `source_region` | Azure region hosting management and scheduler resources; required and distinct from `burst_region` |
| `burst_region` | Azure region hosting transient compute; required and distinct from `source_region` |
| `burst_zone` | Explicit operator-approved availability zone for the exact burst SKU |
| `alternate_burst_placements` | Ordered operator-approved region and zone candidates; never selected automatically |
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

## Regional Capacity Assessment

| Field | Rules |
|---|---|
| `region` and `zone` | Exact approved candidate placement |
| `vm_size` and `image` | Exact burst inputs evaluated for the candidate |
| `sku_state` | `available`, `unavailable`, or `restricted` |
| `restriction_class` | `none`, `subscription`, `location`, `zone`, or `unknown` |
| `regional_quota` | Current usage, limit, required vCPUs, available vCPUs, and projected remainder |
| `family_quota` | Current usage, limit, required vCPUs, available vCPUs, and projected remainder |
| `probe_state` | `not_run`, `allocated`, `allocation_failed`, `inconclusive`, or `cleanup_failed` |
| `assessed_at` | UTC timestamp; required because quota and capacity change |
| `selection_state` | `selected`, `eligible_alternate`, `ineligible`, or `inconclusive` |

## Capacity Probe

| Field | Rules |
|---|---|
| `region`, `zone`, `vm_size`, and `image` | Equal the exact selected burst placement inputs |
| `requested_nodes` | Exactly one |
| `approval_reference` | Reviewed probe plan and explicit cost acknowledgement |
| `started_at` and `completed_at` | UTC timestamps |
| `expires_at` | Bounded lifetime for temporary resources |
| `allocation_state` | `pending`, `allocated`, `failed`, or `timed_out` |
| `failure_class` | Distinguishes allocation, quota, policy, configuration, and unknown failures |
| `cleanup_state` | `pending`, `verified`, or `failed`; only `verified` permits main approval |
| `guarantee` | Always `point_in_time_only` |

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
| `egress_gateway` | One regional Standard NAT Gateway with one managed Standard public IP; associated only with VM-hosting subnets in this site |

## Bastion Public IP

| Field | Rules |
|---|---|
| `owner` | Direct root call to the pinned public-IP AVM; never nested inside the Bastion module |
| `allocation` | Static, Standard, regional, and zonally redundant |
| `ip_tags` | Exactly `FirstPartyUsage = "/Unprivileged"` to match Azure service normalization |
| `consumer` | The single source-region Bastion host; Terraform destroys that dependency first |

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

## CycleCloud Platform Boundary

| Field | Rules |
|---|---|
| `control_identity` | User-assigned identity attached to the VM; subscription Reader plus only the dedicated compute, burst-network, Key Vault, and locker-identity permissions required by CycleCloud |
| `locker_identity` | Separate user-assigned identity with Blob data access only to the private locker account |
| `compute_resource_group` | Dedicated Terraform-owned resource group selected by the `azure` provider account |
| `locker` | Private Terraform-owned storage account and `cyclecloud` container reached through a Blob private endpoint |
| `first_run_state` | `pending`, `bootstrapping`, `complete`, or `failed`; `complete` requires administrator hot-import, TLS import, protected CLI initialization, and provider creation |

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
| `execution_zone` | Equals Demonstration Environment `burst_zone` |
| `output_path` | File under demonstration user's shared home |
| `output_evidence` | Contains remote node name |

## Audit Evidence Set

| Field | Rules |
|---|---|
| `validation_results` | Terraform, Chef, Python, and security gate outcomes |
| `capacity_assessments` | Selected and alternate quota, eligibility, zonal restriction, and probe results |
| `capacity_probe_cleanup` | Probe deletion result and verification timestamp |
| `plan_reference` | Reviewed saved-plan digest and approval |
| `cyclecloud_stack_reference` | Compiled-template, protected-parameter, exact what-if digests, approval, deployment result, and stack cleanup |
| `key_vault_hardening_reference` | Foundation approval for the Key Vault-only policy exclusion plus separate hardening-plan digest, approval, apply result, and observation proving private-only access with no exclusion tag |
| `access_events` | Secret and administrative access events without values |
| `configuration_events` | Convergence and transformation outcomes |
| `cluster_events` | Import, start, node lifecycle, and job evidence |
| `retention_days` | Exactly 90 |

## Cross-entity invariants

1. No Administrative Host or CycleCloud endpoint has public inbound access. The Secret Store may
   allow only the approved runner `/32` during provisioning, may carry `SecurityControl=Ignore`
   only on that resource under explicit approval, and has neither public access nor the tag once
   accepted.
2. Every Azure resource belongs to the feature resource group. Every Terraform-owned resource
   originates from a pinned AVM; only the CycleCloud VM originates from the approved Bicep stack.
3. Cluster, scheduler, template, project, and user identities are consistent across all entities.
4. A deployment cannot enter `provisioned` without an applied reviewed Terraform foundation plan,
   an applied reviewed CycleCloud stack what-if, and an applied reviewed Key Vault hardening plan.
5. Guest state cannot enter `converged` without native validation and second-run idempotency.
6. A headless definition cannot become `valid` if the source combination fails compatibility or
   if the last valid destination would be lost on failure.
7. The scheduler and persistent administration resources are in `source_region`; every acceptance
   compute node is in the distinct `burst_region`.
8. Scheduler and burst-compute image URNs are distinct, exact-version values assigned only to
   their intended roles and validated against their respective regions and VM sizes.
9. Main-environment approval requires sufficient total regional and VM-family quota, exact burst
   zone eligibility, a successful selected-placement capacity probe, and verified probe cleanup.
10. Alternate assessments never mutate the selected region or zone; a changed selection returns
    the environment to `planned` and invalidates prior validation and approval.
