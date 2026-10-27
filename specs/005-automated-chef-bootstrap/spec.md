# Feature Specification: Automated Chef Bootstrap and Convergence

**Feature Branch**: `[005-automated-chef-bootstrap]`

**Created**: 2026-10-23

**Status**: Draft

**Input**: User description: "Ensure the CycleCloud and scheduler VMs receive a complete Chef bootstrap environment during provisioning, with configuration specifications available locally, clear cloud-init and Chef ownership, automatic CycleCloud convergence, dependency-aware scheduler convergence, protected artifacts and credentials, and repeatable idempotency evidence."

## Clarifications

### Session 2026-10-23

- Q: What should trigger the scheduler's first Chef convergence after CycleCloud has imported the cluster and the required credential is available? → A: A governed deployment workflow automatically triggers scheduler convergence after all dependency gates pass.
- Q: After an approved Chef policy changes, how should an already running VM receive that policy? → A: A governed workflow stages the approved artifact and explicitly reruns convergence.
- Q: When bootstrap or first convergence fails after the VM is created, what recovery behavior should the governed workflow use? → A: Permit one governed in-place retry with identical inputs; replace the VM if it fails again.
- Q: Which identities should administer CycleCloud and submit Slurm jobs? → A: `hpcadmin` is the CycleCloud administrator and scheduler-integration identity; `hpcuser01` is the nonprivileged scheduler login and Slurm job-submission identity whose public key and stable UID/GID are propagated by CycleCloud to burst nodes.

### Session 2026-10-24

- Q: How is `hpcuser01` created and granted cluster access when CycleCloud 8.9.3 exposes no
  supported application-user CLI or REST API? → A: Use a governed manual UI gate matching the
  Microsoft reference workflow: the scheduler produces the public key and value-free receipt, an
  operator configures the non-superuser CycleCloud user and cluster access through the supported
  UI, and automation blocks burst-node creation until the resulting node identity is verified.

### Session 2026-10-27

- Q: Which managed identities should the CycleCloud orchestrator and cluster nodes use? → A: The
  CycleCloud VM uses only its system-assigned managed identity for orchestration. The locker
  identity remains an independently created user-assigned managed identity because cluster VMs
  and scale-set members must be able to attach it when they are created.
- Q: Which permissions and scope should the CycleCloud orchestrator receive? → A: Construct the
  custom CycleCloud role from the complete permission set published in the Microsoft Learn
  "Create a custom role and managed identity for CycleCloud" example and assign it at the approved
  burst subscription scope. Grant Key Vault secret-read access separately at the bootstrap vault
  scope. Grant the locker identity only blob-read access at the locker storage-account scope.
- Q: How should the workflow handle the fact that the system-assigned principal does not exist
  until the VM is created? → A: Use a separately reviewed post-create role-assignment plan and make
  first boot wait for those approved assignments through a bounded, fail-closed readiness gate.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Receive a Ready CycleCloud Appliance (Priority: P1)

As a demo operator, I receive a newly deployed CycleCloud VM whose first-run setup and initial Chef
configuration complete automatically, without manually installing Chef, copying cookbooks, or
configuring the Azure subscription.

**Why this priority**: CycleCloud is the control plane for cluster import and scheduler integration.
If it is not fully initialized, every later acceptance activity is blocked.

**Independent Test**: Deploy a new CycleCloud VM from approved inputs and verify that first-run,
provider configuration, policy convergence, and cluster import complete without interactive repair.

**Acceptance Scenarios**:

1. **Given** approved infrastructure, artifacts, secrets, and role assignments, **When** a new
   CycleCloud VM boots, **Then** it installs or verifies the approved configuration client,
   retrieves and validates its approved policy, completes CycleCloud first-run, and performs its
   initial convergence.
2. **Given** successful initial convergence, **When** the operator signs in to CycleCloud, **Then**
   the Azure subscription, managed identities, locker, storage, Marketplace acceptance, and
   `cross-region-demo` cluster are already configured.
3. **Given** a missing, stale, unauthorized, or digest-mismatched policy artifact, **When** bootstrap
   runs, **Then** it fails without running unapproved configuration content or reporting readiness.
4. **Given** a first-run or Chef failure, **When** bootstrap exits, **Then** dependent scheduler
   convergence remains blocked and temporary secrets are absent.
5. **Given** a newly created CycleCloud VM whose system principal does not yet have its approved
   role assignments, **When** first boot begins, **Then** bootstrap waits for a bounded period,
   proceeds only after the exact approved control-plane, storage, and secret-read checks succeed,
   and otherwise fails without reporting readiness.

---

### User Story 2 - Prepare a Dependency-Aware Scheduler (Priority: P2)

As a demo operator, I receive a scheduler VM with all approved convergence tooling and policy
content staged during first boot, while its initial Chef convergence waits until the CycleCloud
cluster, protected `hpcadmin` integration credential, and other required dependencies are
available.

**Why this priority**: The scheduler depends on outputs produced after CycleCloud initialization.
Attempting convergence before those outputs exist creates races, partial configuration, and manual
recovery.

**Independent Test**: Boot a new scheduler before the CycleCloud cluster is imported, verify that
it reaches a safe bootstrap-ready state without partial Slurm configuration, then satisfy the
approved dependency gates and complete convergence.

**Acceptance Scenarios**:

1. **Given** a newly created scheduler VM, **When** first boot completes, **Then** the approved
   configuration client, policy bundle, convergence wrapper, and non-secret node specification are
   present and validated.
2. **Given** the CycleCloud cluster or protected `hpcadmin` integration credential is unavailable,
   **When** the scheduler reaches bootstrap readiness, **Then** it does not begin partial Slurm
   convergence.
3. **Given** CycleCloud convergence, cluster import, required secrets, and access authorization are
   complete, **When** scheduler convergence is authorized, **Then** Slurm, Munge, NFS,
   `hpcuser01` access, and CycleCloud integration are configured in one controlled run.
4. **Given** a failed scheduler convergence, **When** the run exits, **Then** temporary credential
   files are removed and the VM is not reported as converged.

---

### User Story 3 - Reproduce and Audit Convergence (Priority: P3)

As a release reviewer, I can prove exactly which bootstrap and policy artifacts configured each VM,
that protected values were not exposed, and that a repeated Chef run makes zero changes.

**Why this priority**: The demo requires release-candidate-quality evidence, deterministic inputs,
and idempotency rather than a one-time successful configuration.

**Independent Test**: Review a completed evidence set, rerun both role-specific convergences, and
verify approved artifact identities, successful checks, secret-free logs, and zero updates.

**Acceptance Scenarios**:

1. **Given** successful first convergence, **When** the same approved inputs are applied again,
   **Then** each VM reports zero resources updated.
2. **Given** a completed run, **When** evidence is reviewed, **Then** it identifies source revision,
   policy revision, artifact digest, node-specification digest, execution times, results, and
   completion markers without containing credentials.
3. **Given** an existing VM with a complete staged environment, **When** an operator invokes the
   role-specific convergence wrapper, **Then** it uses the same verified policy and specification
   as initial convergence.
4. **Given** a VM whose staged policy or node specification was altered, **When** convergence is
   requested, **Then** execution fails before applying the altered content.

### Edge Cases

- CycleCloud and scheduler VMs boot concurrently, but the scheduler dependency does not yet exist.
- A directly delivered policy bundle or a pinned vendor package does not match its approved digest.
- Bootstrap is interrupted after downloading artifacts but before installation or convergence.
- CycleCloud first-run succeeds but provider creation or cluster import fails.
- The protected `hpcadmin` integration credential exists but the scheduler identity cannot read it.
- The scheduler creates `hpcuser01` but the governed CycleCloud UI gate has not recorded the
  matching public key, stable UID, and non-administrative cluster access before burst nodes are
  created.
- A previously successful VM is rebooted after bootstrap completion.
- An operator reruns bootstrap or convergence while a previous run is active.
- A policy update is approved for an existing VM without replacing that VM.
- Temporary secret cleanup is required after both expected and unexpected failures.
- A bootstrap or first-convergence failure recurs after the one permitted identical-input retry.
- The CycleCloud VM exists but its system-assigned principal is not yet available to the
  post-create role-assignment plan.
- The approved role assignments exist but authorization has not propagated to the management,
  storage, or Key Vault data planes before the bounded bootstrap deadline.
- The independently created locker identity is missing, attached to the orchestrator VM, or has
  permissions broader than blob read at the locker storage-account scope.
- The tenant prerequisite for using the approved custom CycleCloud role cannot be positively
  verified before deployment.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Each Linux VM MUST receive a complete, role-specific configuration bootstrap
  environment during provisioning.
- **FR-002**: The bootstrap environment MUST include an approved configuration client, a
  role-specific policy bundle, a convergence entry point, a non-secret node specification, and
  integrity metadata.
- **FR-003**: Every executable or configuration artifact used during bootstrap or convergence MUST
  be bound to an approved immutable identifier and cryptographic digest.
- **FR-004**: Repository-owned policy bundles, wrappers, and node specifications MUST be delivered
  directly through the protected Azure VM custom-data path and MUST NOT use the Terraform state
  container as a distribution channel. Oversized vendor packages MAY be retrieved from an
  approved immutable HTTPS location only when an approved cryptographic digest is verified before
  installation.
- **FR-005**: Bootstrap MUST verify artifact integrity before installation, extraction, or
  execution.
- **FR-006**: Cloud-init MUST be limited to establishing the execution environment, invoking the
  approved role workflow, recording bounded status, and performing cleanup; substantive steady
  state configuration MUST remain owned by Chef.
- **FR-007**: The existing CycleCloud first-run exception MAY initialize the application account,
  private TLS, protected CLI, and managed-identity provider before CycleCloud Chef convergence.
- **FR-007a**: The CycleCloud orchestrator VM MUST use only its system-assigned managed identity
  for Azure orchestration. The locker identity MUST remain an independently created user-assigned
  managed identity for attachment to CycleCloud-created cluster VMs and scale-set members, and
  MUST NOT be attached to the orchestrator VM.
- **FR-007b**: The orchestrator system identity MUST receive the complete custom-role permission
  set published in the Microsoft Learn "Create a custom role and managed identity for CycleCloud"
  example at the approved burst subscription scope. It MUST receive secret-read access separately
  at the bootstrap Key Vault scope and MUST NOT receive standing secret-write permission. The
  locker identity MUST receive only blob-read access at the locker storage-account scope.
- **FR-007c**: Because the orchestrator principal is created with the VM, its role assignments MUST
  be applied through a separate reviewed, digest-bound post-create infrastructure plan. First boot
  MUST use bounded, fail-closed checks for the approved management, user-delegation, and secret-read
  capabilities; timeout or mismatched identity evidence MUST block first-run and convergence.
- **FR-007d**: The governed preflight MUST positively verify and record the tenant prerequisite
  required by Microsoft for custom-role use before approving the role definition or a replacement
  run; inability to verify that prerequisite MUST block deployment.
- **FR-008**: CycleCloud initial Chef convergence MUST run automatically after successful
  first-run initialization.
- **FR-009**: CycleCloud convergence MUST verify the pinned appliance version and release-matched
  Slurm project before importing exactly one approved cluster.
- **FR-010**: CycleCloud bootstrap readiness MUST remain false until first-run, provider creation,
  policy convergence, and cluster import all succeed.
- **FR-011**: Scheduler first boot MUST stage and validate the complete convergence environment
  without applying partial Slurm configuration before its CycleCloud-generated dependencies exist.
- **FR-012**: Scheduler convergence MUST require successful CycleCloud convergence, successful
  cluster import, the protected `hpcadmin` integration credential, the approved `hpcuser01`
  identity specification, and authorization to retrieve protected inputs.
- **FR-012a**: A governed deployment workflow MUST verify all scheduler dependency gates and
  automatically invoke the staged scheduler convergence entry point; scheduler cloud-init MUST NOT
  poll indefinitely or trigger convergence independently.
- **FR-013**: The scheduler identity MUST receive only the minimum data-plane permissions required
  to retrieve its approved secrets and artifacts.
- **FR-013a**: The existing protected `hpcadmin` CycleCloud application credential MUST be the
  scheduler-to-CycleCloud integration credential and MUST be stored during the approved initial
  Key Vault secret-write lifecycle; neither VM identity may receive standing Key Vault
  secret-write permission.
- **FR-014**: Scheduler convergence MUST configure the approved Slurm and Munge identities,
  package versions, services, NFS paths, `hpcuser01`, private CycleCloud endpoint, direct
  peering behavior, and one-node acceptance limit.
- **FR-014a**: Chef MUST manage the local `hpcuser01` group and user through operating-system
  account-management resources, using UID and GID `11200` and shared home
  `/shared/home/hpcuser01`; no automation may directly edit `/etc/passwd`, `/etc/shadow`, or
  `/etc/group`.
- **FR-014b**: Scheduler convergence MUST generate or preserve the protected `hpcuser01` SSH key
  pair in its shared home and emit a value-free public-identity receipt. Because CycleCloud 8.9.3
  exposes no supported application-user API or CLI, an operator MUST use the supported CycleCloud
  UI to create or update the non-superuser `hpcuser01` record, enable node access with UID `11200`,
  install the exact public key, and grant non-administrative access to `cross-region-demo`.
  The attestation MUST be bound to the current scheduler public-identity receipt and approved
  specification. If the UI requires an application password, the operator MUST use a separately
  generated protected one-time value, require password reset, and discard the value without
  recording it. Burst-node creation MUST remain blocked until the governed workflow accepts the
  operator attestation and verifies the resulting node identity.
- **FR-014c**: Burst nodes created by CycleCloud MUST receive the same `hpcuser01` name, UID
  `11200`, public key, and shared-home semantics used by the scheduler. Acceptance MUST record the
  burst node's observed primary GID, reject identity or ownership conflicts, and require the
  bounded job to succeed; it MUST NOT claim that the CycleCloud UI configures a GID it does not
  expose.
- **FR-015**: Secret values MUST be retrieved only at runtime and MUST NOT be embedded in policy
  bundles or node specifications, source control, Terraform state, routine logs, or secret-free
  evidence. When the release-matched vendor integration supports only a password command-line
  argument, that invocation MUST run once in a root-only, trace-disabled process with process
  visibility restricted to privileged users; the value MUST NOT be persisted in shell history,
  service definitions, status, or evidence.
- **FR-016**: Temporary secrets and derived credential files MUST be removed on success, expected
  failure, interruption, and repeated execution.
- **FR-017**: Rebooting a successfully bootstrapped VM MUST NOT silently rotate credentials,
  reimport application state, or apply unapproved policy changes.
- **FR-018**: Bootstrap and convergence MUST prevent concurrent runs for the same role.
- **FR-019**: Completion markers MUST distinguish environment readiness, first convergence,
  dependency waiting, failure, and verified idempotency.
- **FR-020**: A second convergence with unchanged approved inputs MUST complete with zero resources
  updated on both VMs.
- **FR-021**: Evidence MUST record source revision, policy identity, artifact digest, node
  specification digest, execution timestamps, result, completion state, and second-run update
  count without recording protected values.
- **FR-022**: An altered, stale, missing, unauthorized, or invalid artifact, specification,
  credential reference, or dependency MUST fail closed before dependent configuration is applied.
- **FR-023**: The same staged convergence entry point MUST support initial application, governed
  operator reruns, and idempotency verification.
- **FR-023a**: Existing VMs MUST receive an approved policy update only through an explicit governed
  workflow that stages the digest-bound artifact, reruns convergence, and records fresh evidence;
  VMs MUST NOT periodically discover or silently apply policy updates.
- **FR-024**: Existing private networking, no-public-IP posture, private DNS, Key Vault hardening,
  and VM-only CycleCloud deployment ownership MUST be preserved. Terraform MUST continue to own
  the independent locker identity, custom role definition, and all role assignments; the VM-only
  CycleCloud deployment MUST own the orchestrator system identity as part of the VM.
- **FR-025**: The runbook MUST document bootstrap states, dependency transitions, operator
  verification, safe reruns, failure recovery, and protected evidence transfer.
- **FR-026**: After bootstrap or first convergence fails, the governed workflow MUST permit at most
  one in-place retry using identical approved inputs and MUST preserve both attempts' diagnostic
  evidence.
- **FR-027**: A second failure with identical approved inputs MUST block further in-place retries
  and require a clean VM replacement; manual repair MUST NOT be accepted as clean-boot evidence.

### Key Entities

- **Bootstrap Environment**: The validated, role-specific tools and local content required to run
  approved configuration on one VM.
- **Policy Artifact**: An immutable, digest-bound package containing the approved role policy and
  its required non-secret supporting content.
- **Node Specification**: A non-secret, role-specific set of approved configuration values bound
  to one source revision and environment.
- **Dependency Gate**: The conditions that must be true before a role may begin convergence.
- **Protected Runtime Input**: A secret or credential reference retrieved only when convergence
  requires it.
- **Convergence State**: The role's environment-ready, waiting, converged, failed, or
  idempotency-verified status.
- **Convergence Evidence**: Secret-free records proving input identity, execution result, cleanup,
  and repeated-run behavior.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of newly rebuilt CycleCloud VMs complete first-run, provider setup, initial Chef
  convergence, and cluster import without manual package installation or file copying.
- **SC-002**: 100% of newly created scheduler VMs reach a validated bootstrap-ready state during
  first boot without applying partial Slurm configuration before dependencies are available.
- **SC-003**: Once approved dependencies are available, scheduler convergence completes through one
  documented entry point without interactive package installation or configuration editing.
- **SC-004**: Every executed policy artifact and node specification matches its approved digest;
  all digest mismatch tests fail before configuration changes begin.
- **SC-005**: Repeated convergence on both roles reports zero resources updated with unchanged
  approved inputs.
- **SC-006**: All tested success, failure, interruption, and rerun paths leave zero temporary secret
  or derived credential files behind.
- **SC-007**: No secret value or reversible secret-derived material appears in source control,
  Terraform state, ordinary logs, or secret-free evidence.
- **SC-008**: Operators can determine each VM's bootstrap and convergence state in under one minute
  using documented local status and evidence.
- **SC-009**: The accepted environment retains zero public IP configurations and all existing
  private endpoint, private DNS, identity, and Key Vault hardening controls.
- **SC-010**: A complete clean rebuild through verified second convergence requires no undocumented
  manual intervention.
- **SC-011**: Before the first burst node is accepted, the scheduler public-identity receipt,
  governed CycleCloud UI attestation, and observed burst-node account match on name, UID `11200`,
  public-key fingerprint, shared-home contract, and non-administrative `cross-region-demo` access;
  evidence records the observed primary GID and proves it causes no identity or ownership conflict.
- **SC-012**: Every accepted CycleCloud replacement proves exactly one system-assigned
  orchestrator identity, no orchestrator user-assigned identity, one independent locker identity
  with blob-read access, the approved custom-role assignment at the burst subscription scope,
  separate vault-scoped secret-read access, and successful bounded authorization checks before
  first-run continues.

## Assumptions

- Chef remains the approved configuration-management platform for CycleCloud and scheduler guest
  configuration.
- The CycleCloud application first-run process remains a narrow pre-Chef exception because Chef
  depends on the initialized application and provider.
- CycleCloud initial convergence can complete during first boot because its approved inputs are
  available then.
- The approved Azure tenant has the Microsoft Entra ID P1 prerequisite documented by Microsoft
  for custom-role use; the governed preflight must verify rather than assume this condition.
- The approved burst subscription is the intended assignment boundary for the published
  CycleCloud custom role even when the source and burst regions share that subscription.
- Scheduler convergence remains a separate dependency-gated phase because the CycleCloud cluster
  must exist before scheduler integration is initialized.
- `hpcadmin` is not a scheduler job-submission identity; it is the CycleCloud administrator and
  protected scheduler-integration identity.
- `hpcuser01` is not a local account on the CycleCloud appliance; it is a CycleCloud-managed
  cluster user and the local nonprivileged scheduler account used for SSH and job submission.
- A production environment would normally use LDAP, Active Directory, or another centralized
  identity source to keep UID/GID and SSH authorization consistent; centralized identity
  integration is outside this demo feature.
- Policy artifacts and non-secret node specifications can be distributed through an approved
  private artifact boundary using managed identities.
- Windows administration and CA trust convergence remain governed by their existing workflow and
  are outside this feature except where documentation must describe sequencing.
- High availability, disaster recovery, and additional scaling are outside this feature.
