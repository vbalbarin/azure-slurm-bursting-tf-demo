# Feature Specification: Secure Slurm Bursting Demonstration

**Feature Branch**: `main`

**Created**: 2026-10-07

**Status**: Draft

**Input**: User description: "Create a secure Azure demonstration environment for Slurm bursting
with simulated on-premises and remote networks, CycleCloud, an AlmaLinux scheduler, a Windows
access host, Bastion, centralized secrets, automated headless-cluster preparation, and VM
configuration consistent with the repository README. Use Chef Local for CycleCloud and scheduler
configuration, prefer CycleCloud's own parser for the headless template, and use a guarded Python
helper when no suitable native parser exists."

## Clarifications

### Session 2026-10-07

- Q: When should the required CycleCloud version be selected and pinned? → A: Select the latest
  supported generally available release during planning and pin it for every deployment.
- Q: Which identity model should administrators use for Azure resources, virtual machines, and the
  CycleCloud application? → A: Use Microsoft Entra ID and Azure RBAC for Azure and Key Vault;
  store generated local VM and CycleCloud credentials in Key Vault only where required.
- Q: How should network access to the secret store be restricted? → A: Use a private endpoint only
  and disable public network access.
- Q: What certificate trust model should the private CycleCloud website use? → A: Use a private
  certificate stored in Key Vault and install its trust chain on the Windows administration host.
- Q: How long should security, administrative, and cluster lifecycle audit records be retained
  after the demonstration? → A: Retain them for 90 days.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Provision a Secure Demonstration Environment (Priority: P1)

As an infrastructure operator, I can provision an isolated demonstration environment containing
simulated on-premises and remote networks, protected administrative access, and the required
hosts so that I have a safe foundation for demonstrating cloud bursting.

**Why this priority**: The network, access, host, and secret-management foundation is required
before the Slurm integration can be configured or tested.

**Independent Test**: Provision the environment into an empty approved Azure scope and verify that
all expected resources exist, both networks communicate only over approved paths, administrators
can reach each host through the protected access service, and no VM is directly exposed to the
public internet.

**Acceptance Scenarios**:

1. **Given** an authorized operator and an empty target scope, **When** the environment is
   provisioned, **Then** the simulated on-premises and remote networks, bidirectional connectivity,
   protected access service, secret store, and three requested hosts are available.
2. **Given** the provisioned environment, **When** an unauthorized internet client attempts to
   connect directly to a VM, **Then** the connection is denied.
3. **Given** an authorized administrator, **When** the administrator uses the protected access
   service, **Then** the administrator can connect to the Linux and Windows hosts using credentials
   retrieved through authorized secret-store access.

---

### User Story 2 - Prepare the Headless Slurm Environment (Priority: P1)

As an HPC administrator, I can obtain a headless Slurm cluster definition that matches the
installed CycleCloud release and a configured external scheduler so that the two systems are
ready to operate as one cluster without manual template editing.

**Why this priority**: Correct version matching and consistent scheduler configuration are the
core prerequisites for a repeatable bursting demonstration.

**Independent Test**: Apply local node configuration twice to the CycleCloud and scheduler hosts,
then verify that the second application reports no changes and that the generated cluster
definition is based on the installed release, contains the required Slurm and Munge identities,
omits built-in scheduler and login resources, and can be accepted as a headless cluster definition.

**Acceptance Scenarios**:

1. **Given** a supported CycleCloud release with its matching Slurm project, **When** environment
   preparation completes, **Then** a headless cluster definition is produced without manual edits
   and records the discovered CycleCloud, project, and Slurm versions.
2. **Given** the generated definition, **When** its contents are inspected, **Then** Slurm uses UID
   and GID `11100`, Munge uses UID and GID `11101`, and built-in scheduler, scheduler-HA, login, and
   related parameters are absent.
3. **Given** the configured scheduler and CycleCloud service, **When** the external scheduler
   integration is checked, **Then** both systems use the same cluster name, user identities,
   operating-system family, storage paths, and project version.
4. **Given** both hosts are already configured, **When** local node configuration runs again with
   unchanged inputs, **Then** it reports no changes and preserves the existing valid configuration.

---

### User Story 3 - Demonstrate an End-to-End Burst Job (Priority: P1)

As a demonstration user, I can submit a simple Slurm job from the simulated on-premises scheduler
and observe it execute on a dynamically created remote compute node so that cloud bursting is
proven end to end.

**Why this priority**: A completed remote job is the principal business outcome and the clearest
evidence that the environment works.

**Independent Test**: Submit a one-node hello-world job as the test user, observe one remote
compute node become available, and verify that the resulting output identifies that compute node.

**Acceptance Scenarios**:

1. **Given** an idle headless cluster and an authorized test user, **When** the user submits a
   one-node job to the configured partition, **Then** a remote compute node is created and the job
   enters execution without manual host configuration.
2. **Given** a running burst job, **When** the job finishes, **Then** its output is available in the
   test user's shared home and identifies the remote compute node that ran it.
3. **Given** the completed job and no further work, **When** the environment reaches its configured
   idle period, **Then** the transient compute node is removed while the scheduler remains usable.

---

### User Story 4 - Access and Operate CycleCloud Privately (Priority: P2)

As an HPC administrator, I can use a Windows administration host reached through the protected
access service to open the CycleCloud application privately, manage the demonstration cluster,
and inspect node activity.

**Why this priority**: Private graphical administration improves the demonstration and avoids
exposing the CycleCloud application publicly, but the core integration can be verified separately.

**Independent Test**: Connect to the Windows host through the protected access service, open the
private CycleCloud application endpoint, authenticate with an authorized account, and view the
headless cluster and its nodes.

**Acceptance Scenarios**:

1. **Given** an authorized administrator, **When** the administrator connects to the Windows host
   through the protected access service, **Then** the CycleCloud application is reachable by its
   private name and presents a valid secure connection.
2. **Given** an authenticated administrator, **When** the demonstration cluster is opened, **Then**
   the administrator can review configuration and node state without exposing the application to
   the public internet.

### Edge Cases

- The selected Azure region does not offer a required VM image, VM size, current supported
  CycleCloud release, or Azure service capability.
- The latest generally available CycleCloud release is incompatible with the Slurm project or
  operating-system image selected for the scheduler.
- A matching Slurm cluster template cannot be discovered or parsed for the installed release.
- A generated headless definition already lacks one or more removable sections or contains more
  than one matching section.
- The installed CycleCloud release does not expose a supported parser for its cluster template.
- A configuration-file processor receives malformed input, is interrupted before replacement, or
  is run repeatedly against an already-correct file.
- The required Slurm, Munge, or test-user identity conflicts with an existing identity.
- Network peering exists but routing, name resolution, or security rules block a required flow.
- Controlled outbound access is unavailable while hosts need approved packages or release assets.
- A secret or key is missing, inaccessible to the intended identity, expired, or rotated during
  environment preparation.
- A burst node cannot mount `/sched` or `/shared`, or sees ownership inconsistent with the
  scheduler's users and groups.
- Validation or change review fails before deployment; deployment remains blocked.
- A partial provisioning attempt is retried and must converge without duplicating resources or
  replacing retained resources unexpectedly.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The environment MUST provide two non-overlapping virtual networks named
  `vnet-onpremises` and `vnet-remote` that represent the local and remote sites.
- **FR-002**: The two networks MUST have bidirectional private connectivity and MUST resolve the
  private names required by the scheduler, CycleCloud service, Windows host, and compute nodes.
- **FR-003**: The environment MUST separate host, protected-access, and workload traffic into
  appropriately sized subnets and restrict each subnet to documented required flows.
- **FR-004**: During planning, the latest generally available CycleCloud release supported in the
  selected region and compatible with the selected Slurm project MUST be selected, recorded, and
  pinned. Every deployment of this feature MUST use that exact version.
- **FR-005**: The simulated on-premises network MUST contain one supported AlmaLinux HPC scheduler
  host and one supported Windows administration host.
- **FR-006**: The Windows host MUST be able to access the CycleCloud application over private
  networking, and the CycleCloud application MUST NOT be directly reachable from the public
  internet. The application MUST present a certificate valid for its private name, with the
  certificate stored in the secret store and its trust chain installed on the Windows host.
- **FR-007**: A managed protected-access service MUST provide administrative SSH and remote desktop
  access to the hosts without assigning public IP addresses to those hosts.
- **FR-008**: A centralized secret store MUST contain all generated administrative passwords,
  private keys, service credentials, and demonstration-user credentials required by the
  environment. Local credentials MUST be created only where a VM or CycleCloud requires them. The
  secret store MUST be reachable only through a private endpoint, and public network access MUST
  be disabled.
- **FR-009**: Administrators MUST use Microsoft Entra ID and least-privilege Azure RBAC for Azure
  resource and secret-store access. Secret access MUST be auditable, and secret values MUST NOT
  appear in source control, deployment outputs, logs, plans, or general VM metadata.
- **FR-010**: The CycleCloud and scheduler hosts MUST be prepared consistently with the repository
  guidance through Chef Local without interactive configuration steps after deployment.
- **FR-011**: The environment MUST discover the installed CycleCloud release and its associated
  Slurm project and template rather than assuming a fixed template path or project version.
- **FR-012**: The environment MUST produce a headless cluster definition from the discovered
  release-matched template without manual editing, using a supported CycleCloud parser when one is
  available and a dedicated Python configuration-file processor otherwise.
- **FR-013**: The headless definition MUST configure the Slurm user with UID and GID `11100` and
  the Munge user with UID and GID `11101`.
- **FR-014**: The headless definition MUST omit built-in scheduler, scheduler high-availability,
  login, and all README-identified scheduler and login parameter sections.
- **FR-015**: Headless-definition generation MUST fail with an actionable error when the source
  template is unavailable, ambiguous, malformed, incompatible, or cannot be transformed safely;
  it MUST NOT emit a success-shaped partial definition. The fallback processor MUST inspect current
  content, validate generated content before replacement, update atomically only when content
  changes, preserve the last valid file on failure, and make no change when rerun with unchanged
  inputs.
- **FR-016**: The CycleCloud service MUST contain one imported headless Slurm cluster whose name is
  configurable and consistently applied to all integration points.
- **FR-017**: The scheduler MUST provide Slurm, Munge, shared `/sched` and `/shared` storage, and an
  external-scheduler configuration compatible with the discovered project version.
- **FR-018**: The cluster MUST configure compute nodes to use the scheduler's private address for
  `/sched` and `/shared`, use the same supported operating-system family as the scheduler, and not
  use built-in network storage.
- **FR-019**: The cluster MUST disable the return proxy when direct private connectivity between
  the networks is available.
- **FR-020**: A test user MUST have a consistent numeric identity, group membership, home
  ownership, cluster authorization, and public key across the scheduler and remote compute nodes.
- **FR-021**: The scheduler MUST integrate with the CycleCloud private endpoint using credentials
  retrieved through authorized secret access, and authentication failures MUST be explicit.
- **FR-022**: The environment MUST permit only the outbound connectivity required to obtain
  approved release assets, operating-system packages, and cluster dependencies.
- **FR-023**: The completed environment MUST support submission of a one-node test job whose output
  is written to shared storage and identifies the remote node that executed it.
- **FR-024**: The demonstration MUST begin with a single remote compute node per test job and MUST
  remove the node after an operator-configurable idle period; high availability, disaster recovery,
  and additional scale testing are out of scope.
- **FR-025**: Every infrastructure change MUST comply with the current project constitution,
  including exclusive use of pinned Azure Verified Modules and successful validation and change
  review before deployment.
- **FR-026**: Provisioning and Chef Local configuration MUST be repeatable and MUST converge without
  duplicating resources, rewriting already-correct files, or requiring manual correction after a
  successful run.
- **FR-027**: The environment MUST emit an inventory containing private host names and addresses,
  application access instructions, selected product versions, cluster name, and validation
  evidence without exposing secret values.
- **FR-028**: Operational events for secret access, administrative sign-in, cluster preparation,
  and burst-node lifecycle MUST be retained and available for review for 90 days after the
  demonstration.
- **FR-029**: The fallback Python processor MUST be limited to transforming the node-consumed
  headless cluster configuration file and MUST NOT provision, modify, or delete Azure resources.
- **FR-030**: The reason a native CycleCloud parser cannot perform the required transformation,
  along with the fallback processor's inputs, outputs, validation, and failure behavior, MUST be
  documented and reviewable before the fallback is used.

### Inferred Requirements Proposed for Stakeholder Approval

The following requirements are inferred from the repository guidance and are included in this
draft for approval: private cross-network name resolution (FR-002), subnet-level traffic
restriction (FR-003), no public VM or application exposure (FR-006 and FR-007), release discovery
and compatibility checks (FR-011 and FR-015), shared `/sched` and `/shared` storage (FR-017 and
FR-018), disabled return proxy over direct connectivity (FR-019), consistent numeric identities
(FR-020), controlled outbound access (FR-022), one-node demonstration scope (FR-024), repeatable
convergence (FR-026), operator inventory (FR-027), auditable operations (FR-028), and guarded
fallback processing with documented justification (FR-029 and FR-030).

### Key Entities *(include if feature involves data)*

- **Demonstration Environment**: The complete isolated Azure scope, including region, resource
  names, selected versions, validation status, and lifecycle state.
- **Network Site**: A simulated site with an address range, subnets, private name-resolution rules,
  approved traffic flows, and a peering relationship to the other site.
- **Administrative Host**: A Linux or Windows host identified by role, private name, private
  address, operating-system image, access policy, and credential references.
- **Secret**: A password, private key, certificate, or service credential with an owner, intended
  consumers, rotation state, and access-audit history; its value is never part of environment
  inventory.
- **Headless Cluster Definition**: A release-matched cluster description identified by source
  project version, Slurm version, required identities, removed sections, and validation status.
- **Slurm Cluster**: The externally scheduled cluster identified by cluster name, scheduler,
  partitions, shared-storage endpoints, compute-node image, and lifecycle state.
- **Demonstration User**: The authorized job submitter identified by user name, UID, group,
  public key, home path, and cluster access state.
- **Burst Job**: A submitted workload identified by job ID, user, partition, requested node count,
  execution node, status, timestamps, and output location.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An authorized operator can provision the complete demonstration environment from an
  empty approved scope in 90 minutes or less without interactive host-configuration steps.
- **SC-002**: 100% of deployments are blocked unless required validation and change review
  complete successfully against the exact configuration being deployed.
- **SC-003**: All three hosts, the CycleCloud application, and the secret store have zero direct
  inbound exposure from the public internet while authorized administrators can reach each
  intended management surface.
- **SC-004**: The release-matched headless cluster definition is generated and accepted without
  manual file editing in 100% of supported-version test runs, whether a native parser or approved
  fallback is required.
- **SC-005**: An authorized user can submit a one-node demonstration job and receive output naming
  the remote execution node within 15 minutes under normal regional capacity conditions.
- **SC-006**: The demonstration job succeeds on its first submission in at least 9 of 10 clean
  environment test runs, excluding documented external regional-capacity failures.
- **SC-007**: Every credential and private key required by the environment is centrally protected,
  and zero secret values appear in source control, deployment output, logs, or operator inventory.
- **SC-008**: A second provisioning and node-configuration run with unchanged inputs makes zero
  unintended environment changes, performs zero unnecessary configuration-file replacements, and
  requires no manual repair.
- **SC-009**: An HPC administrator can use the Windows host to reach the private CycleCloud
  application and identify the demonstration cluster and burst-node state within 5 minutes.
- **SC-010**: The environment records enough inventory and operational evidence for an independent
  reviewer to confirm the deployed versions, access model, network boundaries, successful
  validation, and completed burst job without accessing secret values at any time during the
  90-day retention period.

## Assumptions

- The target Azure subscription, region, naming prefix, and authorized operator identities will be
  supplied during planning or deployment; one resource group and one region are sufficient for
  this non-high-availability demonstration.
- Non-overlapping private address ranges and cost-conscious VM sizes will be selected during
  planning based on regional availability and the minimum supported product requirements.
- "Most current release" means the latest generally available CycleCloud release supported in the
  selected region and compatible with the selected Slurm project when planning occurs; preview
  releases are excluded. The selected version remains pinned for all deployments of this feature.
- The latest supported AlmaLinux HPC image is preferred for the scheduler and matching compute
  nodes. The latest supported Windows Server image is sufficient for the administration host.
- Azure regional capacity, an authorized subscription, required service quotas, and controlled
  outbound access to approved product and package sources are available.
- The demonstration uses one external scheduler, one CycleCloud host, one Windows host, and at
  most one burst compute node for the acceptance test. High availability, disaster recovery,
  production hardening, performance benchmarking, and multi-node scale testing are out of scope.
- The scheduler provides the shared storage required by the repository guidance; a separate
  managed storage service is out of scope unless planning identifies a product requirement.
- Chef Local is the selected configuration-management mode for both the scheduler and CycleCloud
  hosts; it manages node configuration only and does not manage Azure control-plane resources.
- A supported parser supplied by the installed CycleCloud release is preferred for interpreting
  and transforming its cluster definition. A dedicated Python processor is used only when no
  suitable native parser exists and remains subject to the constitution's exception controls.
- Chef content and any fallback processor will be validated and tested for first application,
  repeated application, already-compliant state, malformed input, and safe interruption before
  they are used on the demonstration hosts.
- Security and reliability requirements in the constitution take precedence over demonstration
  convenience and over the repository's legacy script-based setup instructions.
