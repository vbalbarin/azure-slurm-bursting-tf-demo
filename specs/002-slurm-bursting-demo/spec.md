# Feature Specification: Secure Slurm Bursting Demonstration

**Feature Branch**: `main`

**Created**: 2026-10-07

**Status**: Draft

**Input**: User description: "Create a secure cross-region Azure demonstration environment for
Slurm bursting from a scheduler and administration plane in one configurable Azure region to
transient compute in a separately configurable Azure region with less constrained capacity. Use
CycleCloud, an AlmaLinux scheduler, a Windows access host, Bastion, centralized secrets, automated
headless-cluster preparation, and VM configuration consistent with the repository README. Use
Chef Local for CycleCloud and scheduler configuration, prefer CycleCloud's own parser for the
headless template, and use a guarded Python helper when no suitable native parser exists."

## Clarifications

### Session 2026-10-07

- Q: When should the required CycleCloud version be selected and pinned? → A: Select the latest
  supported generally available release during planning and pin it for every deployment.
- Q: Which identity model should administrators use for Azure resources, virtual machines, and the
  CycleCloud application? → A: Use Microsoft Entra ID and Azure RBAC for Azure and Key Vault;
  store generated local VM and CycleCloud credentials in Key Vault only where required.
- Q: How should network access to the secret store be restricted? → A: Use a private endpoint only
  in the accepted environment and disable public network access. During initial credential
  creation only, permit the approved runner's exact `/32`, then require a separately reviewed
  hardening plan that disables public access before acceptance.
- Q: How should the released CycleCloud Marketplace appliance be deployed when its required image
  data disk cannot be represented by the approved Terraform VM module? → A: Terraform owns the NIC
  and every surrounding resource; a source-pinned Bicep deployment stack owns only the CycleCloud
  VM, Marketplace plan, OS disk, required image data disk, user-assigned control identity
  attachment, and secure custom-data handoff.
- Q: What certificate trust model should the private CycleCloud website use? → A: Use a private
  certificate stored in Key Vault and install its trust chain on the Windows administration host.
- Q: How long should security, administrative, and cluster lifecycle audit records be retained
  after the demonstration? → A: Retain them for 90 days.
- Q: Which source topology should the demonstration implement? → A: Implement Azure-region-to-
  Azure-region bursting only; an existing on-premises source is a future extension.

### Session 2026-10-20

- Q: How should the bounded Key Vault provisioning window coexist with the active management-group
  policy that otherwise forces public access off? → A: Apply `SecurityControl=Ignore` only to the
  Key Vault in the initial, explicitly approved foundation plan. Keep default deny and the exact
  runner `/32`, then remove the tag in the same separately approved hardening plan that disables
  public access and clears every IP rule. Never apply the exclusion to the resource group.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Provision a Secure Demonstration Environment (Priority: P1)

As an infrastructure operator, I can provision an isolated demonstration environment spanning a
configurable Azure source region and a separately configurable Azure burst region, with protected
administrative access and the required hosts, so that I have a safe foundation for demonstrating
capacity-aware cross-region cloud bursting.

**Why this priority**: The network, access, host, and secret-management foundation is required
before the Slurm integration can be configured or tested.

**Independent Test**: Provision the environment into an empty approved Azure scope and verify that
all expected resources exist, both networks communicate only over approved paths, administrators
can reach each host through the protected access service, and no VM is directly exposed to the
public internet.

**Acceptance Scenarios**:

1. **Given** an authorized operator, two approved Azure regions, and an empty target scope,
   **When** the environment is provisioned, **Then** the source-region and burst-region networks,
   bidirectional private cross-region connectivity, protected access service, secret store, and
   three requested hosts are available.
2. **Given** the provisioned environment, **When** an unauthorized internet client attempts to
   connect directly to a VM, **Then** the connection is denied.
3. **Given** an authorized administrator, **When** the administrator uses the protected access
   service, **Then** the administrator can connect to the Linux and Windows hosts using credentials
   retrieved through authorized secret-store access.
4. **Given** the exact planned VM counts, sizes, regions, and burst availability zone, **When**
   pre-deployment validation runs, **Then** it separately reports regional and VM-family quota
   headroom, SKU and image eligibility, zonal restrictions, and current allocation-probe status.
5. **Given** that the selected burst region or zone cannot satisfy a quota, eligibility, or
   point-in-time allocation check, **When** approved alternate-region candidates are assessed,
   **Then** the operator receives actionable candidate results without any deployment input being
   changed automatically.

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

As a demonstration user, I can submit a simple Slurm job from the scheduler in the Azure source
region and observe it execute on a dynamically created compute node in the selected Azure burst
region so that cross-region cloud bursting is proven end to end.

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
- The subscription has enough total regional quota but insufficient quota for the selected VM
  family, or vice versa.
- A burst SKU is available in a region but unavailable or restricted in the selected availability
  zone.
- A capacity probe succeeds for one node but later multi-node allocation is constrained; the
  evidence must not represent the probe as a capacity guarantee.
- A capacity probe fails after creating one or more temporary resources, or cleanup cannot be
  confirmed.
- An alternate region satisfies static eligibility and quota checks but has not passed a
  point-in-time allocation probe.
- The source and burst regions are identical, or either region lacks a required service, image,
  SKU, quota, or capacity.
- Global peering is unavailable between the selected regions or measured cross-region latency is
  unsuitable for the scheduler, shared-storage, or cluster-management path.
- The latest generally available CycleCloud release is incompatible with the Slurm project or
  operating-system image selected for the scheduler.
- The scheduler image supports the source-region scheduler size but the burst-compute image does
  not support the selected burst-region size, or the two images do not provide a compatible
  operating-system family and major release.
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
  `vnet-source` and `vnet-burst` in two distinct, independently configurable Azure regions.
- **FR-002**: The two networks MUST have bidirectional private cross-region connectivity over the
  Azure backbone and MUST resolve the private names required by the scheduler, CycleCloud service,
  Windows host, and compute nodes.
- **FR-003**: The environment MUST separate host, protected-access, and workload traffic into
  appropriately sized subnets and restrict each subnet to documented required flows.
- **FR-004**: During planning, the latest generally available CycleCloud release supported in the
  selected source and burst regions and compatible with the selected Slurm project MUST be
  selected, recorded, and pinned. Every deployment of this feature MUST use that exact version.
- **FR-004a**: The pinned CycleCloud Marketplace VM MUST be deployed from a version-controlled
  Bicep template through a deployment stack. Terraform MUST own its NIC and all surrounding
  infrastructure. The stack MUST own only the VM, Marketplace plan, OS disk, required image data
  disk at LUN 0, user-assigned control identity attachment, and secure custom-data handoff.
  Deployment requires an exact digest-approved
  what-if, drift reconciliation uses a new what-if, and cleanup deletes the stack-owned VM before
  Terraform-owned dependencies.
- **FR-004b**: Terraform MUST create a dedicated CycleCloud compute resource group, a private
  locker storage account and container, separate control and locker user-assigned identities,
  private Blob DNS, and least-privilege role assignments. First boot MUST non-interactively create
  the local `hpcadmin` application administrator, install private-name TLS from protected Key
  Vault secrets, initialize a protected CLI configuration, and create the managed-identity Azure
  provider account before guest convergence can import a cluster.
- **FR-005**: The source-region network MUST contain one supported AlmaLinux scheduler host using
  a pinned image compatible with the selected scheduler VM size, and one supported Windows
  administration host.
- **FR-006**: The Windows host MUST be able to access the CycleCloud application over private
  networking, and the CycleCloud application MUST NOT be directly reachable from the public
  internet. The application MUST present a certificate valid for its private name, with the
  password-protected PFX stored in the secret store and only its generated private CA certificate
  installed in the Windows trusted-root store.
- **FR-007**: Azure Bastion Standard MUST provide supported browser or native-client RDP access
  only to the Windows administration VM through a root-owned Standard public IP passed into the
  Bastion module, without assigning public IP addresses to any VM. Acceptance MUST require at
  least one supported Bastion RDP path to authenticate successfully. Portal/browser
  interoperability SHOULD be recorded, but a browser-client session failure MUST NOT block
  acceptance when native-client Bastion RDP authentication succeeds. The public IP configuration
  MUST explicitly model Azure's reserved `FirstPartyUsage = "/Unprivileged"` IP tag so a refresh
  does not propose replacement. The Windows VM MUST be the jump host for SSH to the scheduler and
  CycleCloud hosts and for HTTPS access to the private CycleCloud application. Direct Bastion SSH
  to the scheduler or CycleCloud hosts MUST be denied.
- **FR-008**: A centralized secret store MUST contain all generated administrative passwords,
  private keys, service credentials, and demonstration-user credentials required by the
  environment. Local credentials MUST be created only where a VM or CycleCloud requires them. The
  secret store MUST be reachable only through a private endpoint, and public network access MUST
  be disabled in the accepted environment. Initial secret creation MAY temporarily enable the
  public endpoint with a default-deny firewall containing only the approved runner's exact `/32`.
  When the active management-group policy requires its documented exclusion for this bounded
  access, only the secret-store resource MAY carry `SecurityControl=Ignore`, and the exact
  foundation-plan approval MUST explicitly authorize that exclusion. A separately generated,
  reviewed, digest-approved hardening plan MUST remove that rule, disable public network access,
  and remove the exclusion tag in the same apply before infrastructure acceptance or guest
  convergence. The resource group and every other resource MUST remain untagged.
- **FR-009**: Administrators MUST use Microsoft Entra ID and least-privilege Azure RBAC for Azure
  resource and secret-store access. Secret access MUST be auditable, and secret values MUST NOT
  appear in source control, deployment outputs, logs, plans, or general VM metadata.
- **FR-010**: The CycleCloud and scheduler hosts MUST be prepared consistently with the repository
  guidance without interactive configuration steps after deployment. CycleCloud first-run
  application initialization MUST complete through cloud-init before Chef Local uses the protected
  `/etc/cyclecloud/cli.ini`; Chef MUST fail explicitly when that file or the `azure` provider
  account is unavailable.
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
  `/sched` and `/shared`, use an independently pinned image that is compatible with the selected
  burst-compute VM size and the scheduler's operating-system family and major release, and not use
  built-in network storage.
- **FR-019**: The cluster MUST disable the return proxy when direct private connectivity between
  the networks is available.
- **FR-020**: A test user MUST have a consistent numeric identity, group membership, home
  ownership, cluster authorization, and public key across the scheduler and remote compute nodes.
- **FR-021**: The scheduler MUST integrate with the CycleCloud private endpoint using credentials
  retrieved through authorized secret access, and authentication failures MUST be explicit.
- **FR-022**: The environment MUST permit only the outbound connectivity required to obtain
  approved release assets, operating-system packages, and cluster dependencies. Because an Azure
  NAT Gateway cannot serve a peered VNET in another region, the self-contained demonstration MUST
  provide one regional NAT Gateway for the source access and management subnets and a second
  regional NAT Gateway for the burst compute subnet. Private-endpoint and Bastion subnets MUST NOT
  be associated with either workload NAT Gateway.
- **FR-023**: The completed environment MUST support submission of a one-node test job whose output
  is written to shared storage and identifies the remote node that executed it.
- **FR-024**: The demonstration MUST begin with a single remote compute node per test job and MUST
  remove the node after an operator-configurable idle period; high availability, disaster recovery,
  and additional scale testing are out of scope.
- **FR-031**: The source and burst regions MUST be explicit inputs, MUST be different, and MUST be
  recorded in inventory and acceptance evidence.
- **FR-032**: Deployment MUST fail before apply when either selected region lacks required
  capabilities, the image or VM SKU assigned to each role, quota, or approved cross-region
  connectivity; it MUST NOT silently select another region, image, or SKU.
- **FR-033**: The acceptance job's evidence MUST prove that the scheduler ran in the source region
  and the transient execution node ran in the selected burst region.
- **FR-034**: The scheduler and burst-compute image references MUST be separate explicit inputs,
  MUST each be pinned to an exact version, MUST be validated in their assigned regions against
  their assigned VM sizes, and MUST be recorded by role in inventory and acceptance evidence.
- **FR-035**: Pre-deployment validation MUST calculate the vCPUs required by every planned role and
  MUST compare them separately with both total regional vCPU quota and the applicable regional
  VM-family quota, including current usage, limit, remaining quota, required quota, and projected
  remaining quota.
- **FR-036**: Pre-deployment validation MUST distinguish an unavailable SKU, a subscription
  restriction, insufficient total regional quota, insufficient VM-family quota, a zonal
  restriction, and a point-in-time allocation failure, and MUST provide an actionable reason for
  each failed gate.
- **FR-037**: Burst placement MUST include an explicit operator-approved availability zone.
  Pre-deployment validation MUST prove that the exact burst SKU and image are eligible in the
  selected region and zone and MUST account for location- and zone-specific restrictions before
  any demonstration infrastructure is applied.
- **FR-038**: Before the main environment is approved, an authorized operator MUST be able to run
  a controlled, one-node capacity probe using the exact burst region, availability zone, VM size,
  and image. The probe MUST require explicit cost acknowledgement, record its start time and
  outcome, use no public ingress, have a bounded lifetime, and state that success is point-in-time
  evidence rather than a future or multi-node capacity guarantee.
- **FR-039**: Every capacity probe MUST use the same governed infrastructure review and deployment
  controls as the demonstration, MUST remove all probe-owned resources after success or failure,
  and MUST block main-environment approval when cleanup cannot be confirmed.
- **FR-040**: Operators MUST be able to provide an ordered list of approved alternate burst-region
  and zone candidates. Validation MUST assess each candidate for the exact burst image, SKU,
  zonal restrictions, total and family quota, and probe status; MUST identify eligible candidates
  and the reason each other candidate is ineligible or inconclusive; and MUST NOT discover,
  select, substitute, or deploy a candidate automatically.
- **FR-041**: Selecting a recommended alternate candidate MUST require an operator to update the
  protected deployment inputs and rerun the complete validation, capacity-probe, plan-review, and
  approval sequence.
- **FR-042**: Inventory and acceptance evidence MUST record quota measurements, required vCPUs,
  region and zone eligibility, restriction classifications, capacity-probe timestamps and
  outcomes, cleanup confirmation, assessed alternate candidates, and the operator-selected region
  and zone without exposing secret values.
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
- **Regional Network Site**: An Azure source or burst region with an address range, subnets,
  private name-resolution rules, approved traffic flows, and a global-peering relationship to the
  other region.
- **Administrative Host**: A Linux or Windows host identified by role, private name, private
  address, operating-system image, access policy, and credential references.
- **Secret**: A password, private key, certificate, or service credential with an owner, intended
  consumers, rotation state, and access-audit history; its value is never part of environment
  inventory.
- **Headless Cluster Definition**: A release-matched cluster description identified by source
  project version, Slurm version, required identities, removed sections, and validation status.
- **Slurm Cluster**: The externally scheduled cluster identified by cluster name, scheduler,
  partitions, shared-storage endpoints, independently pinned scheduler and compute-node images,
  their compatibility status, and lifecycle state.
- **Demonstration User**: The authorized job submitter identified by user name, UID, group,
  public key, home path, and cluster access state.
- **Burst Job**: A submitted workload identified by job ID, user, partition, requested node count,
  execution node, status, timestamps, and output location.
- **Regional Capacity Assessment**: A time-stamped evaluation of one approved region and zone,
  including exact SKU and image eligibility, restriction classifications, total and VM-family
  quota measurements, required vCPUs, probe status, and operator-selection state.
- **Capacity Probe**: A controlled temporary one-node allocation identified by exact placement and
  image inputs, approval reference, start and completion times, allocation outcome, failure
  classification, expiration boundary, and verified cleanup state.

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
- **SC-011**: Every successful acceptance run records two distinct configured Azure regions and
  proves that the scheduler and transient execution node ran in their assigned source and burst
  regions respectively.
- **SC-012**: Every approved deployment records distinct pinned scheduler and burst-compute image
  references and proves before apply that each image is available in its assigned region,
  compatible with its assigned VM size, and compatible with the other role's operating-system
  family and major release.
- **SC-013**: Every main-environment approval includes a complete quota assessment in which 100%
  of planned roles have sufficient total regional and VM-family quota for their required vCPUs.
- **SC-014**: Every burst-region assessment reports the exact region and zone and classifies 100%
  of observed SKU, subscription, quota, zonal, and allocation failures without describing one
  class as another.
- **SC-015**: Every capacity probe either confirms allocation of one exact burst node and removes
  all temporary resources within 15 minutes, or fails with actionable evidence and confirmed
  cleanup; an unconfirmed cleanup blocks the main deployment.
- **SC-016**: When the selected burst placement fails, an operator can identify the eligibility,
  quota headroom, probe status, and rejection reason for every approved alternate candidate within
  10 minutes, with zero automatic changes to deployment inputs.
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

- The target Azure subscription, distinct source and burst regions, naming prefix, and authorized
  operator identities will be supplied during planning or deployment; one resource group spanning
  both regions is sufficient for this non-high-availability demonstration.
- Non-overlapping private address ranges and cost-conscious VM sizes will be selected during
  planning based on regional availability and the minimum supported product requirements.
- "Most current release" means the latest generally available CycleCloud release supported across
  both selected regions and compatible with the selected Slurm project when planning occurs;
  preview releases are excluded. The selected version remains pinned for all deployments.
- The source region hosts the scheduler, Windows administration host, Bastion, CycleCloud, Key
  Vault private endpoint, and management services; the burst region hosts transient compute.
- Region and zone selection is explicit and operator-approved. Candidates are supplied in an
  operator-approved order. Automatic region discovery, failover, substitution, and deployment are
  out of scope.
- Existing on-premises scheduler connectivity is a future extension and is not implemented by
  this feature.
- The scheduler and burst compute nodes use independently pinned images from the same supported
  AlmaLinux family and compatible major release. The scheduler image is selected for compatibility
  with its source-region general-purpose VM size, while the burst image is the supported HPC image
  for its burst-region compute size. The latest supported Windows Server image is sufficient for
  the administration host.
- An authorized subscription and controlled outbound access to approved product and package
  sources are available. Regional and VM-family quota, zonal eligibility, and point-in-time
  capacity are validation outcomes rather than assumptions.
- A successful one-node capacity probe is temporary evidence only; it does not reserve capacity or
  guarantee later or multi-node allocation. Workloads that require guaranteed placement require a
  separately approved capacity-reservation design outside this bounded demonstration.
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
