# Feature Specification: Terraform State Backend Bootstrap

**Feature Branch**: `003-terraform-backend-bootstrap`

**Created**: 2026-10-13

**Status**: Draft

**Input**: User description: "using Terraform state backend bootstrap proposal"

## Clarifications

### Session 2026-10-13

- Q: Which network mode should be the default when an operator does not explicitly select one? →
  A: Restricted-public access limited to explicitly approved operator or runner addresses; private
  endpoint mode remains selectable.
- Q: Where should the bootstrap root's own state live after the new backend is successfully created
  and validated? → A: Migrate it to `<environment>/bootstrap.tfstate`, retain the protected local
  copy only until migration is verified, and migrate back to protected local state before backend
  removal.
- Q: How should the bootstrap handle an organization that already provides an approved Terraform
  state backend? → A: Create a dedicated backend by default; an explicit existing-backend mode is
  validate-only and never imports, modifies, owns, or deletes organizational resources.
- Q: Which principal should receive Blob data-plane access by default for newly created backends? →
  A: An approved Microsoft Entra operator security group, with an optional workload identity for
  automation; direct current-user assignment requires separate explicit approval.
- Q: How should globally unique backend names obtain their collision-resistant suffix? → A: Require
  an approved operator-supplied lowercase alphanumeric uniqueness code that is stable, non-secret,
  and independent of bootstrap state.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Bootstrap a Governed State Backend (Priority: P1)

As an authorized infrastructure operator, I can create a dedicated state backend before deploying
the demonstration so that the main environment and temporary capacity probe have durable,
recoverable state without relying on storage keys or an already-existing project backend.

**Why this priority**: Neither deployment root can initialize or produce a reviewed plan until its
backend exists and is reachable. This is the prerequisite that blocked the previous evidence run.

**Independent Test**: Starting in an approved subscription with no project backend, complete the
bootstrap workflow and verify that the expected backend scope, storage service, private state
container, access assignment, and non-secret backend coordinates exist while no credential is
written to source, output, logs, or evidence.

**Acceptance Scenarios**:

1. **Given** an authorized operator, approved subscription, region, naming inputs, tags, and network
   access mode, **When** bootstrap is approved and completed, **Then** a dedicated backend and
   private state container exist with encryption, access control, and deletion protection applied.
2. **Given** the backend does not exist, **When** the operator reviews the bootstrap change,
   **Then** all resources, names, access assignments, network controls, and outputs are visible
   before creation.
3. **Given** bootstrap completes, **When** outputs and evidence are inspected, **Then** they contain
   only non-secret backend coordinates, resource identifiers, selected network mode, and validation
   results.
4. **Given** the same approved inputs and an already-compliant backend, **When** bootstrap is
   evaluated again, **Then** no infrastructure change is proposed.
5. **Given** an approved organizational backend, **When** the operator explicitly selects
   existing-backend mode, **Then** readiness and state separation are validated without importing,
   changing, or assuming lifecycle ownership of the backend resources.

---

### User Story 2 - Initialize Isolated Demo and Probe State (Priority: P1)

As a deployment operator, I can initialize both demonstration roots through my approved identity
with distinct state namespaces so that main-environment operations and temporary-probe cleanup
cannot corrupt or replace one another.

**Why this priority**: A backend is useful only when both dependent workflows can authenticate,
lock state, and maintain strict state separation.

**Independent Test**: Using the bootstrap outputs and an approved operator identity, initialize the
main and capacity-probe workflows non-interactively, perform state read/write/lock checks, and
verify that each workflow uses its own environment-scoped state object.

**Acceptance Scenarios**:

1. **Given** a successfully bootstrapped backend and a deployment operator who belongs to the
   approved operator group, **When** both dependent workflows initialize, **Then** each
   authenticates through the operator's approved identity without a storage key or shared-access
   token.
2. **Given** one environment, **When** both workflows initialize, **Then** the main environment uses
   `<environment>/main.tfstate` and the capacity probe uses
   `<environment>/capacity-probe.tfstate`.
3. **Given** one workflow holds its state lock, **When** a conflicting operation targets the same
   state, **Then** the conflicting operation is rejected without state corruption.
4. **Given** the main and probe workflows are initialized, **When** either state object changes,
   **Then** the other state object remains unchanged.
5. **Given** backend readiness has passed, **When** bootstrap state migration completes, **Then**
   bootstrap, main, and capacity-probe state use three distinct environment-scoped objects and the
   protected local bootstrap copy is removed only after migration is verified.

---

### User Story 3 - Validate Access Before Deployment (Priority: P2)

As an operator or reviewer, I can validate identity, authorization, DNS, routing, container access,
and locking before planning demo resources so that backend failures stop early with an actionable
classification.

**Why this priority**: A backend that exists but cannot be reached or authorized produces confusing
late failures and can strand temporary resources.

**Independent Test**: Run backend readiness checks against valid and deliberately invalid identity,
role, DNS, route, container, and state-key configurations and verify that every invalid condition
fails before a demo or probe plan is created.

**Acceptance Scenarios**:

1. **Given** the operator lacks Blob data access, **When** readiness is checked, **Then** validation
   fails with an authorization classification that distinguishes data-plane access from
   subscription management access.
2. **Given** a private endpoint without a working private DNS or network path, **When** readiness is
   checked from the execution environment, **Then** validation fails with DNS or connectivity
   guidance before downstream initialization.
3. **Given** restricted public access that does not include the execution source, **When** readiness
   is checked, **Then** validation fails with a network-access classification.
4. **Given** an incorrect account, container, or state namespace, **When** readiness is checked,
   **Then** validation identifies the missing or mismatched coordinate without falling back to
   local state.

---

### User Story 4 - Preserve and Recover Backend Control (Priority: P2)

As an accountable operator, I can preserve bootstrap state, authorize a replacement operator, and
prevent premature backend deletion so that the project remains recoverable after laptop, container,
or personnel changes.

**Why this priority**: The backend is a durable project dependency and must outlive any one local
execution environment.

**Independent Test**: Retain protected bootstrap state, authorize a second operator, verify that the
second operator can access both dependent state namespaces without receiving a storage secret, and
confirm that backend teardown is blocked while either namespace manages resources.

**Acceptance Scenarios**:

1. **Given** the original operator is unavailable, **When** an approved replacement operator is
   granted the required role, **Then** that operator can initialize and recover both workflows
   without a storage key or shared-access token.
2. **Given** either state namespace still contains managed resources, **When** backend removal is
   requested, **Then** removal is rejected and identifies the blocking namespace.
3. **Given** both dependent environments are empty and cleanup is verified, **When** backend removal
   is reviewed, **Then** the operator can see all proposed deletions and must explicitly approve
   them.
4. **Given** protected bootstrap state is missing or inconsistent, **When** a bootstrap mutation or
   teardown is attempted, **Then** the workflow stops and requires recovery rather than creating a
   competing backend.

### Edge Cases

- The requested globally unique storage name is already owned by another Azure customer.
- The supplied uniqueness code is invalid, reused in a conflicting naming scope, or cannot produce
  an available global name.
- The workload, environment, region, and instance components exceed a resource-specific name limit.
- The selected region is unsupported by the approved naming map or storage service.
- The storage account exists but the expected container does not.
- The container exists under an account with incompatible security, encryption, or network policy.
- An existing organizational backend matches some, but not all, required controls.
- The operator has subscription Owner or Contributor but lacks Blob data-plane access.
- A role assignment succeeds but has not propagated when readiness validation begins.
- Public network access is disabled while the operator is outside the private network path.
- The execution source's public address changes after restricted public access is approved.
- DNS resolves the public endpoint when private-endpoint mode requires a private address.
- Main and probe initialization are accidentally given the same state key.
- A stale lock remains after an interrupted operation.
- Bootstrap succeeds but protected local bootstrap state is lost before it is retained.
- Bootstrap-state migration fails or cannot be verified after backend creation.
- Backend teardown is requested while a failed probe still has resources recorded in state.
- A bootstrap retry uses a different subscription, tenant, naming scope, or network mode.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The feature MUST provide a bootstrap lifecycle that is independent of the backend it
  creates.
- **FR-002**: The feature MUST require explicit approved subscription, tenant, region, workload,
  environment, instance, four-to-six-character lowercase alphanumeric uniqueness code, and tagging
  inputs; MUST default an omitted network mode to `restricted_public`; MUST require an approved
  operator-group input only in managed mode; and MUST allow an optional workload-identity input for
  automation.
- **FR-003**: The feature MUST generate backend resource names from a shared structured naming
  contract containing resource type, workload, environment, region, and instance components.
- **FR-004**: The naming contract MUST enforce each resource type's character and length rules and
  MUST use the approved uniqueness code to resolve global-name collisions deterministically without
  exposing tenant or subscription identifiers or depending on retained state.
- **FR-005**: The feature MUST default to creating one dedicated backend resource scope, encrypted
  storage service, and non-public state container, and MUST provide an explicit validate-only mode
  for an approved existing organizational backend.
- **FR-006**: The backend MUST use identity-based authentication by default and MUST NOT require
  storage keys or shared-access tokens for ordinary state operations.
- **FR-007**: The feature MUST disable anonymous access and MUST apply all storage encryption
  controls required by current project governance.
- **FR-008**: The feature MUST grant the approved Microsoft Entra operator security group the
  least-privilege Blob data-plane role required for state read, write, delete, and lock operations
  and MUST support the same least-privilege assignment for an optional approved workload identity.
- **FR-009**: The feature MUST distinguish Blob data-plane authorization from subscription
  management roles in validation and operator guidance.
- **FR-010**: The feature MUST default to an approved restricted-public network mode that limits
  backend access to explicitly approved execution sources.
- **FR-011**: The feature MUST support an approved private network mode with private name resolution
  and a pre-existing reachable private network path; managed mode MUST require explicit subnet and
  Blob private-DNS-zone inputs, while existing mode MUST validate the equivalent approved network
  coordinates supplied through its existing-backend input.
- **FR-012**: The selected network mode MUST fail closed; the feature MUST NOT silently enable
  unrestricted public access when the approved path is unavailable.
- **FR-013**: The feature MUST validate backend account existence, container existence, identity,
  authorization, DNS resolution, routing, Blob operations, and state locking from the actual
  execution environment before any dependent plan is created, and readiness evidence MUST bind
  those results to a non-secret digest of the observed runner and network context.
- **FR-014**: Readiness failures MUST identify at least these classes separately: missing backend,
  missing container, authentication failure, authorization failure, DNS failure, network failure,
  state-key collision, and locking failure.
- **FR-015**: The feature MUST emit non-secret backend coordinates sufficient to initialize
  dependent workflows without interactive prompts.
- **FR-016**: Backend outputs MUST include the subscription, tenant, account, container, selected
  network mode, bootstrap state key, main state key, probe state key, and relevant resource
  identifiers.
- **FR-017**: The main state key MUST be `<environment>/main.tfstate`.
- **FR-018**: The capacity-probe state key MUST be
  `<environment>/capacity-probe.tfstate`.
- **FR-019**: The feature MUST reject identical, empty, absolute, parent-relative, or
  environment-incompatible state keys.
- **FR-020**: Initialization MUST authenticate as the approved active identity, run
  non-interactively, and refuse any fallback to unapproved local state or secret-based
  authentication.
- **FR-021**: The bootstrap's own state MUST begin as a protected local artifact with restrictive
  access and integrity evidence, then migrate to `<environment>/bootstrap.tfstate` only after
  preliminary readiness succeeds with every pre-migration check passed and only migration and
  locking recorded as `not_run`; final readiness MUST require successful migration and locking.
  The active local state file and recognized local state backup files MUST be retained with
  restrictive permissions until remote pull, lineage and resource-count equality, a no-change
  plan, and locking are verified. Before logical deletion, the workflow MUST record only their
  content-free digests as evidence; afterward it MUST verify that the named active and backup files
  no longer exist. Sanitization of underlying storage media remains the responsibility of the
  approved host or container platform.
- **FR-022**: Bootstrap state, plans, and evidence MUST exclude credentials, access tokens, storage
  keys, shared-access tokens, and protected application inputs.
- **FR-023**: Bootstrap apply MUST consume the exact reviewed bootstrap plan, MUST rely on
  Terraform's stale-state rejection, and MUST reject a plan whose SHA-256 digest does not match an
  external approval record created after plan generation.
- **FR-024**: Repeated bootstrap evaluation with unchanged inputs and an already-compliant backend
  MUST propose no infrastructure change.
- **FR-025**: Any change to subscription, tenant, naming scope, network mode, access principal,
  backend coordinates, bootstrap state, observed runner/network context, or reviewed plan MUST
  invalidate dependent approval.
- **FR-026**: For a backend created and owned by this feature, the feature MUST protect the storage
  service and state container from accidental deletion while either dependent state namespace
  records managed resources.
- **FR-027**: Removal of a backend created and owned by this feature MUST require verified empty main
  and probe state namespaces, successful migration of bootstrap state back to a protected local
  artifact, an exact reviewed removal plan, and explicit approval.
- **FR-028**: The feature MUST support authorizing a replacement operator through approved group
  membership or approved group replacement without distributing a storage secret.
- **FR-029**: Existing-backend mode MUST preserve organizational backend data, remain validate-only,
  and MUST NOT import, mutate, replace, assume ownership of, or delete a pre-existing backend
  resource.
- **FR-030**: The feature MUST record secret-free evidence for bootstrap validation, plan review,
  apply, readiness checks, downstream initialization, access recovery, and any removal attempt.
- **FR-031**: The operator documentation MUST distinguish backend bootstrap, backend readiness,
  dependent initialization, ordinary deployment, and backend removal as separate approval stages.
- **FR-032**: The existing main and capacity-probe workflows MUST remain unable to create plans
  until backend readiness succeeds for their exact approved coordinates.
- **FR-033**: Bootstrap, main, and capacity-probe state MUST use the distinct keys
  `<environment>/bootstrap.tfstate`, `<environment>/main.tfstate`, and
  `<environment>/capacity-probe.tfstate` during ordinary operation.

### Key Entities

- **Bootstrap Configuration**: The approved subscription, tenant, location, naming components,
  non-secret uniqueness code, network mode, access principals, tags, and policy choices used to
  define one backend.
- **Backend Resource Set**: The resource scope, encrypted storage service, private state container,
  network controls, access assignments, deletion protections, and ownership mode that hold project
  state.
- **Backend Coordinates**: The non-secret values that identify the subscription, tenant, storage
  service, container, network mode, and state keys consumed by dependent workflows.
- **State Namespace**: One environment-scoped state object and its lock behavior, classified as
  bootstrap, main deployment, or capacity probe.
- **Access Principal**: An approved human or workload identity granted least-privilege Blob
  data-plane access through an operator security group or optional automation assignment; direct
  user assignment is exceptional and requires explicit approval.
- **Bootstrap State Artifact**: The protected local record required to evaluate, update, recover,
  or remove the backend resource set.
- **Backend Readiness Evidence**: Secret-free results for existence, identity, authorization, DNS,
  network, Blob operation, key separation, and locking checks.
- **Bootstrap Approval**: The reviewed-plan digest, evidence references, accountable reviewer, and
  decision authorizing a bootstrap apply or removal.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An authorized operator with approved inputs can create a new backend and obtain
  validated non-secret coordinates in 20 minutes or less, measured from bootstrap initialization
  through final coordinate validation as active execution time; separately recorded cloud
  role-propagation and authorized plan-approval wait intervals are excluded. Command failures,
  investigation, retries, and ordinary execution time are not excluded.
- **SC-002**: In acceptance testing, 100% of missing-account, missing-container, unauthorized,
  unreachable, incorrectly resolved, colliding-key, and lock-conflict cases stop before a dependent
  plan is created.
- **SC-003**: Bootstrap, main, and capacity-probe workflows use three distinct environment-scoped
  state objects under the approved identity after migration in every tested run.
- **SC-004**: Repeating bootstrap evaluation with unchanged inputs produces zero proposed resource
  changes.
- **SC-005**: A second approved operator can recover access to the main and capacity-probe
  dependent namespaces within 15 minutes, measured from the replacement operator's authenticated
  start through successful read-and-lock verification, without receiving a storage key,
  shared-access token, or other stored credential.
- **SC-006**: Automated inspection of source, outputs, ordinary logs, plans, and evidence finds zero
  access tokens, credentials, storage keys, shared-access tokens, or protected demo inputs.
- **SC-007**: Every tested backend removal attempt is blocked while either dependent namespace
  records managed resources.
- **SC-008**: In every acceptance run, bootstrap, preliminary readiness, migration and final
  readiness, dependent initialization and deployment, recovery, unlock, and removal stages record
  their required approval references using only documented commands, with zero undocumented
  recovery commands or workflow substitutions.
- **SC-009**: All generated backend names pass their Azure resource constraints, remain stable
  across repeated evaluation and state recovery, and avoid collisions in the approved deployment
  scope.

## Assumptions

- Operators already have an approved Azure tenant and subscription and sufficient management-plane
  authority to create the backend resources and access assignment.
- Human operators receive ordinary state access through an approved Microsoft Entra security group;
  an approved workload identity may receive a separate assignment for automation, and direct user
  assignment is not created without explicit approval.
- Restricted-public mode is intended for explicitly approved operator or runner source addresses,
  not unrestricted internet access, and is the default when no network mode is explicitly selected.
- Private network mode depends on an approved private network path that exists independently of the
  demo backend bootstrap.
- Bootstrap state begins as a protected local artifact because no project backend exists yet,
  migrates into the validated backend for ordinary operation, and migrates back to protected local
  state before backend removal.
- Organizational pre-existing backends may be selected only through explicit validate-only mode,
  must satisfy every applicable readiness requirement, and remain outside this feature's lifecycle
  ownership.
- High availability, geo-redundant disaster recovery, and scale beyond the demo's state workload
  remain outside scope under the project constitution.
- The broader migration of all existing demo resource names remains a separate feature; this
  feature establishes the naming contract required for new backend resources.
- The uniqueness code is an approved non-secret naming input retained with environment
  configuration and is not derived from tenant, subscription, credential, or bootstrap-state data.
