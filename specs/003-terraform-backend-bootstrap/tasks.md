---

description: "Implementation tasks for the Terraform state backend bootstrap feature"
---

# Tasks: Terraform State Backend Bootstrap

**Input**: Design documents from `/specs/003-terraform-backend-bootstrap/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: The specification requires independent tests for all four user stories, deterministic
native Terraform failure-class coverage, JSON Schema tests, policy tests, migration and locking
integration tests, plan-digest and stale-plan rejection, and timed live Azure acceptance. Test
tasks therefore precede implementation tasks in each story.

**Organization**: Tasks are grouped by user story so each increment can be implemented, validated,
and reviewed independently.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel after prior-phase dependencies complete because it changes different
  files and does not depend on another incomplete task in the same group.
- **[Story]**: Maps the task to a user story in `spec.md`.
- Every task names the exact file or files it changes.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish protected state storage and repository-level exclusions before any bootstrap
state or plan can be created.

- [X] T001 [P] Add the `azure-slurm-bursting-tf-demo-state` named volume at `/state` plus `STATE_ROOT=/state` and `BOOTSTRAP_STATE_ROOT=/state/terraform-backend` container variables in `.devcontainer/devcontainer.json`, keeping `/state` separate from `/evidence`
- [X] T002 [P] Validate the `/state` mount, repair ownership without deleting retained content, set the root and bootstrap directory to mode `0700`, and fail with rebuild guidance when unavailable in `.devcontainer/post-create.sh`
- [X] T003 [P] Add explicit exclusions for protected backend configuration, readiness inputs, local plans, state backups, and migration artifacts while retaining only `*.example` files in `.gitignore`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish reusable contract-validation fixtures and constitutional policy checks used
by every story.

**CRITICAL**: No user story implementation begins until these tests exist and fail for missing
bootstrap implementation.

- [X] T004 [P] Add JSON Schema tests that resolve relative schema references, enforce formats and status/failure invariants, reject additional properties, and validate representative coordinate, readiness, lifecycle, and post-generation plan-approval documents against every schema in `specs/003-terraform-backend-bootstrap/contracts/` in `tests/end-to-end/test_backend_state_contracts.py`
- [X] T005 [P] Add policy tests that reject direct Azure resource blocks, local/custom modules, unpinned AVM sources, shared-key/SAS backend settings, anonymous access, and unrestricted public fallback in the bootstrap root in `tests/policy/test_constitution.py`

**Checkpoint**: Contract and policy tests define the fail-closed implementation boundary.

---

## Phase 3: User Story 1 - Bootstrap a Governed State Backend (Priority: P1) MVP

**Goal**: Create or validate one governed backend with deterministic names, Entra-based access,
secure network controls, deletion protection, and non-secret coordinates.

**Independent Test**: Starting with no project backend, create a saved managed-mode plan and verify
the exact AVM resources, names, private container, security controls, role assignments, lock, and
outputs; apply only that reviewed plan and confirm a second plan is empty. In existing mode, verify
the plan creates, imports, mutates, locks, and deletes nothing.

### Tests for User Story 1

> Write these tests first and confirm they fail before implementing the bootstrap root.

- [X] T006 [P] [US1] Add Terraform naming tests for the exact resource-group pattern `rg-<workload>-<environment>-<region-code>-<instance>`, storage pattern `st<workload-token><environment-token><region-code><instance><uniqueness>`, lowercase alphanumeric storage names of 3-24 characters, two-digit instances, fixed `tfstate` container, invalid region mappings, overlength components, and four-to-six-character lowercase alphanumeric uniqueness codes in `terraform/bootstrap/tests/naming.tftest.hcl`
- [X] T007 [P] [US1] Add mocked managed restricted-public tests for direct pinned AVMs, private container, Entra role assignments, default-deny firewall, explicit public IPv4 CIDRs, disabled shared keys and anonymous access, TLS 1.2+, HTTPS, infrastructure encryption, versioning, seven-day blob/container soft delete, tags, and `CanNotDelete` lock in `terraform/bootstrap/tests/managed-backend.tftest.hcl`
- [X] T008 [P] [US1] Add mocked private-mode tests that require an existing reachable subnet and `privatelink.blob.core.windows.net` private DNS zone, disable public access, configure the storage AVM embedded Blob private endpoint, reject public CIDRs, and never create VNet or DNS resources in `terraform/bootstrap/tests/private-backend.tftest.hcl`
- [X] T009 [P] [US1] Add mocked existing-mode tests that require explicit approved coordinates and prove zero resources, module instances, role assignments, locks, imports, mutations, or deletions are proposed in `terraform/bootstrap/tests/existing-backend.tftest.hcl`

### Implementation for User Story 1

- [X] T010 [US1] Declare Terraform `>= 1.10, < 2.0`, the AzureRM backend transition point, AzureRM provider compatibility, and pinned AzAPI `2.12.0` without raising the existing roots' Terraform floor in `terraform/bootstrap/versions.tf` and `terraform/bootstrap/providers.tf`
- [X] T011 [US1] Implement the complete input contract in `terraform/bootstrap/variables.tf`: `subscription_id` is an approved Azure subscription UUID; `tenant_id` is an Entra tenant UUID; `location` has a defined region code; `workload_name` is a lowercase ALZ workload token constrained by generated names; `environment_name` is lowercase alphanumeric or hyphen and a valid Blob key prefix; `instance` is an integer 0-99; `uniqueness_code` is four to six lowercase alphanumeric characters; `ownership_mode` is `managed` or `existing` and defaults to `managed`; `network_mode` is `restricted_public` or `private` and defaults to `restricted_public`; managed mode requires an existing Entra security-group `operator_group_object_id`; `workload_identity_object_id` is an optional service-principal object ID; restricted-public mode requires one or more public IPv4 CIDRs and rejects RFC1918 and catch-all ranges; private managed mode requires existing subnet and Blob private-DNS-zone IDs and rejects public CIDRs; private existing mode validates equivalent coordinates inside required `existing_backend`; tags are approved non-secret governance tags; and cross-field validation rejects conflicting ownership inputs
- [X] T012 [US1] Implement the approved location-to-region-code map, normalized ALZ naming, two-digit instance code, deterministic state keys `<environment>/bootstrap.tfstate`, `<environment>/main.tfstate`, and `<environment>/capacity-probe.tfstate`, plus pairwise-distinct/nonempty/nonabsolute/non-parent-relative key checks in `terraform/bootstrap/locals.tf`
- [X] T013 [P] [US1] Call only `Azure/avm-res-resources-resourcegroup/azurerm` version `0.4.0` in managed mode with the deterministic resource-group name, approved location, and tags in `terraform/bootstrap/resource-group.tf`
- [X] T014 [P] [US1] Call only `Azure/avm-res-storage-storageaccount/azurerm` version `0.10.0` in managed mode to create the `tfstate` private container, container-scoped `Storage Blob Data Contributor` assignments for the operator group and optional workload identity, restricted-public or private networking, disabled shared-key and anonymous access, TLS/HTTPS/encryption controls, versioning, seven-day blob/container soft delete, and ordinary-operation `CanNotDelete` lock in `terraform/bootstrap/storage.tf`
- [X] T015 [P] [US1] Implement read-only existing-backend coordinate lookup and fail-closed compatibility checks without resources, module instances, imports, assignments, locks, unlocks, or deletion paths in `terraform/bootstrap/existing-backend.tf`
- [X] T016 [US1] Emit only schema version, ownership mode, approved subscription and tenant IDs, resource-group/account/container names, selected network mode, the three exact state keys, and non-secret resource IDs while marking no credential or protected value as an output in `terraform/bootstrap/outputs.tf`
- [X] T017 [P] [US1] Provide a non-secret managed restricted-public example, documented private and existing alternatives, required governance tags, and placeholder identity/resource IDs without real coordinates in `terraform/bootstrap/bootstrap.tfvars.example`
- [X] T018 [P] [US1] Provide an ignored AzureRM backend override template with `use_azuread_auth = true`, `use_cli = true`, no key/SAS fields, and the bootstrap-key placeholder in `terraform/bootstrap/backend.azurerm.tf.example`
- [X] T019 [US1] Extend `tests/end-to-end/test_backend_state_contracts.py` to compare `terraform output -json` shape and state-key semantics with the coordinate contract, reject changed plan digests and malformed approval records, and prove no storage key, SAS, token, password, certificate, or protected input is emitted
- [X] T020 [US1] Document protected local-state initialization, saved-plan generation, post-generation SHA-256 approval record creation, immediate digest verification, exact `terraform apply <saved-plan>`, Terraform stale-state rejection, second no-change plan, managed/private/existing review expectations, and the prohibition on custom Bash/Python readiness, lifecycle, provisioning, or apply implementation in `README.md`

**Checkpoint**: User Story 1 can independently create a governed backend or validate an existing
one and produce non-secret coordinates.

---

## Phase 4: User Story 2 - Initialize Isolated Demo and Probe State (Priority: P1)

**Goal**: Migrate bootstrap state and initialize bootstrap, main, and capacity-probe roots with
three isolated Entra-authenticated namespaces and native locking.

**Independent Test**: With valid backend coordinates and an approved identity, migrate protected
bootstrap state to Azure Blob, initialize all three roots non-interactively, demonstrate distinct
objects and lock conflict behavior, verify a no-change bootstrap plan, and retain/remove the local
copy only at the required lifecycle points.

### Tests for User Story 2

> Write these tests first and confirm they fail before implementing backend initialization.

- [X] T021 [P] [US2] Add deterministic tests for the three exact environment-scoped keys, rejection of empty/absolute/parent-relative/colliding/environment-mismatched keys, Entra-only partial backend settings, and absence of local-state fallback in `tests/end-to-end/test_backend_state_contracts.py`
- [X] T022 [P] [US2] Add `specs/003-terraform-backend-bootstrap/contracts/backend-migration-acceptance.schema.json` plus opt-in evidence-contract tests for an externally and directly operator-executed local-to-remote bootstrap migration, validating secret-free records of source/coordinate binding, local/remote lineage and resource-count equality, remote pull, second no-change plan, Terraform stale-plan rejection, lock acquisition/release, deliberate lock conflict, exact namespace isolation, verification status, and protected-copy retention on failed verification in `tests/end-to-end/test_backend_migration_evidence.py` and `tests/end-to-end/test_backend_state_contracts.py`; the Python test MUST NOT invoke Terraform, Azure CLI, migration, provisioning, apply, unlock, destroy, or any other control-plane operation

### Implementation for User Story 2

- [X] T023 [P] [US2] Add the tracked Entra-authenticated partial backend configuration example for `<environment>/main.tfstate`, with no credential or secret-authentication setting, in `terraform/backend.hcl.example`
- [X] T024 [P] [US2] Add the tracked Entra-authenticated partial backend configuration example for `<environment>/capacity-probe.tfstate`, with no credential or secret-authentication setting, in `terraform/capacity-probe/backend.hcl.example`
- [X] T025 [US2] Add an executable migration fixture with a harmless local Terraform value and output so the direct operator-executed acceptance sequence can create mode-`0600` local state, install an ignored copy of `terraform/bootstrap/backend.azurerm.tf.example`, exercise `terraform init -migrate-state` rather than `-reconfigure`, and compare state lineage/resource counts in `tests/end-to-end/fixtures/backend-migration/main.tf`
- [X] T026 [US2] Add direct noninteractive Entra backend initialization commands and exact `<environment>/main.tfstate` assertions for the main root without changing or wrapping its apply path in `README.md`
- [X] T027 [US2] Add direct noninteractive Entra backend initialization commands and exact `<environment>/capacity-probe.tfstate` assertions for the capacity-probe root without changing or wrapping its cleanup/apply path in `README.md`
- [X] T028 [US2] Document exact active local state and recognized backup paths, restrictive permissions throughout retention, `terraform init -migrate-state`, remote pull and lineage/resource-count verification, no-change and lock-conflict checks, distinct dependent initialization, digest-only retained evidence, removal only after verification, post-deletion absence checks for every named active/backup file, and approved host/container responsibility for underlying media sanitization in `README.md`

**Checkpoint**: User Story 2 proves isolated state and locking without storage keys or copied
credentials.

---

## Phase 5: User Story 3 - Validate Access Before Deployment (Priority: P2)

**Goal**: Produce stable, secret-free readiness evidence and block both dependent plans before
resource evaluation when identity, coordinates, authorization, DNS, network, container, key, age,
commit, migration, or locking checks fail.

**Independent Test**: Run readiness against valid and deliberately invalid fixtures for every
failure class, then prove only evidence that is `ready`, no older than one hour, and matches source
commit, environment, identity scope, and exact coordinates permits either dependent plan.

### Tests for User Story 3

> Write these tests first and confirm they fail before implementing readiness.

- [X] T029 [P] [US3] Add native Terraform classification tests for `missing_backend`, `missing_container`, `authentication_failed`, `authorization_failed`, `dns_failed`, `network_failed`, `state_key_collision`, `lock_failed`, and `configuration_mismatch`, including role-propagation delay, public/private DNS mismatches, changed source address, changed private-network context, changed resolved endpoint, stale or incomplete observations, wrong command IDs, preliminary `not_run` migration/locking with null exit code and empty observed value, rejection of contradictory `not_run` provenance, and final all-passed assertions in `terraform/bootstrap/tests/readiness.tftest.hcl`
- [X] T030 [P] [US3] Add main-root gate tests for missing, malformed, failed, older-than-one-hour, wrong-commit, wrong-environment, wrong-identity, wrong-coordinate, wrong execution-context digest, colliding-key, incomplete-migration, and failed-lock readiness evidence in `terraform/tests/backend-readiness.tftest.hcl`
- [X] T031 [P] [US3] Add capacity-probe gate tests for the same fail-closed readiness and execution-context cases plus a valid ready fixture in `terraform/capacity-probe/tests/backend-readiness.tftest.hcl`

### Implementation for User Story 3

- [X] T032 [US3] Implement protected schema-conforming readiness-assertion inputs plus native Terraform locals, checks, and preconditions that validate source/coordinate digests, assessment and observation freshness, stable command IDs, exit codes, bounded observed values, active tenant/subscription, coordinate shape, account/container results, DNS endpoint mode, actual-runner reachability, expected group/workload role assignments, active-identity Blob access, key separation, migration, locking, and execution-context binding; classify every stable failure without any custom Bash/Python helper in `terraform/bootstrap/readiness.tf` and `terraform/bootstrap/variables.tf`
- [X] T033 [US3] Emit schema-conforming readiness output bound to the exact 40-character source commit, assessed UTC time, active identity scope, environment, backend coordinates, and non-secret execution context; enforce a one-hour maximum age and `status=ready` only with `failure_class=none`; and keep the canonical JSON SHA-256 in an adjacent sidecar rather than a self-referential field in `terraform/bootstrap/readiness.tf` and `terraform/bootstrap/outputs.tf`
- [X] T034 [P] [US3] Add readiness evidence and current protected execution-context digest inputs plus native pre-resource checks for status, age, source commit, environment, identity scope, coordinates, runner-context equality, three distinct keys, migration, and locking in `terraform/variables.tf` and `terraform/backend-readiness.tf`
- [X] T035 [P] [US3] Add the same readiness evidence, current execution-context digest, and native pre-resource checks for the capacity probe in `terraform/capacity-probe/variables.tf` and `terraform/capacity-probe/backend-readiness.tf`
- [X] T036 [P] [US3] Add a secret-free example readiness document containing execution-context binding plus adjacent evidence/context digest naming contracts for the main root, with actual readiness files remaining ignored and external to source, in `terraform/backend-readiness.json.example`
- [X] T037 [P] [US3] Add a secret-free example readiness document containing execution-context binding plus adjacent evidence/context digest naming contracts for the capacity-probe root, with actual readiness files remaining ignored and external to source, in `terraform/capacity-probe/backend-readiness.json.example`
- [X] T038 [US3] Add bootstrap Terraform initialization/validation/tests, native readiness/lifecycle classification tests, all JSON contract tests, and both dependent readiness test suites to `Makefile`
- [X] T039 [US3] Document exact direct Azure CLI, DNS, HTTP, state-pull, no-change-plan, and lock-conflict commands; schema-conforming assertion capture with stable command IDs, timestamps, exit codes, bounded non-secret observations, and no raw output; execution-context canonicalization and digest comparison; stable classifications and remediation; one-hour validity; identity-versus-management-role distinction; canonical JSON plus adjacent digest output; and fail-closed plan gates in `README.md`

**Checkpoint**: User Story 3 fails before either dependent plan starts unless exact current
readiness is proven.

---

## Phase 6: User Story 4 - Preserve and Recover Backend Control (Priority: P2)

**Goal**: Recover access through approved group membership and prevent unlock or deletion until
dependent state is empty and bootstrap state is safely local again.

**Independent Test**: Authorize a replacement operator without distributing a storage secret;
prove that operator can initialize/read/lock all namespaces; prove removal fails while main or
probe manages resources or local bootstrap state is missing; then perform reverse migration,
separate unlock review, and separate destroy review.

### Tests for User Story 4

> Write these tests first and confirm they fail before implementing recovery and removal gates.

- [X] T040 [P] [US4] Add native Terraform lifecycle tests for replacement operator-group access assertions, absent/inconsistent protected bootstrap state, blocking main/probe resource counts, failed reverse migration, state-digest mismatch, existing-mode removal rejection, separate unlock/destroy actions, and stable lifecycle failure classes in `terraform/bootstrap/tests/lifecycle.tftest.hcl`
- [X] T041 [P] [US4] Add `specs/003-terraform-backend-bootstrap/contracts/backend-live-acceptance.schema.json` plus opt-in evidence-contract tests for externally and directly operator-executed second-operator recovery, bootstrap and recovery timing limits, all three namespace initialization/read/lock results, secret-free lock access, reverse migration to mode-`0600` local state, unlock-only plan digest and approval, separate destroy-plan digest and approval, stale-plan rejection, backend absence after approved cleanup, and zero secret-hygiene violations in `tests/end-to-end/test_backend_live_acceptance_evidence.py` and `tests/end-to-end/test_backend_state_contracts.py`; the Python test MUST validate only schema-bound secret-free records and MUST NOT invoke Terraform, Azure CLI, migration, provisioning, apply, unlock, destroy, or any other control-plane operation

### Implementation for User Story 4

- [X] T042 [US4] Add protected lifecycle-assertion inputs and native preconditions requiring verified zero managed resources in main and capacity-probe state, successful local reverse migration, matching protected state digest, explicit action (`migrate_local`, `unlock`, or `destroy`), managed ownership, and approval reference without accepting a not-yet-created plan digest as a Terraform input in `terraform/bootstrap/variables.tf` and `terraform/bootstrap/lifecycle.tf`
- [X] T043 [US4] Make managed lock removal possible only for the explicit reviewed `unlock` action, reject destroy while the lock remains, and expose no unlock/destroy path in existing mode in `terraform/bootstrap/storage.tf` and `terraform/bootstrap/existing-backend.tf`
- [X] T044 [US4] Emit `backend-lifecycle.schema.json` output that reports blocking namespace, managed-resource count, bootstrap state location/digest match, reverse-migration status, ownership-mode prohibition, action, and approval reference without adding lifecycle fields to ordinary readiness evidence in `terraform/bootstrap/lifecycle.tf` and `terraform/bootstrap/outputs.tf`
- [X] T045 [US4] Extend contract tests to validate lifecycle evidence and post-generation create/unlock/destroy approval records, reject mismatched source/input/plan digests, and prove that only digests—not plans or state content—enter evidence in `tests/end-to-end/test_backend_state_contracts.py`
- [X] T046 [US4] Document group-based replacement access, recovery when protected state is missing, dependent-state emptiness verification, reverse `terraform init -migrate-state`, ignored-override removal, separate post-generation unlock approval and digest verification, separate post-generation destroy approval and digest verification, Terraform stale-state rejection, and the absence of any existing-mode teardown operation in `README.md`

**Checkpoint**: User Story 4 proves durable operator recovery and fail-closed managed removal.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Complete source gates, operator guidance, evidence hygiene, and end-to-end acceptance
across all stories.

- [X] T047 [P] Update the tracked acceptance sequence and expected artifacts to match implemented commands, exact file names, and managed/existing workflows in `specs/003-terraform-backend-bootstrap/quickstart.md`
- [X] T048 [P] Create the tracked evidence runbook with backend bootstrap, readiness, migration, recovery, and removal stages, explicitly prohibiting reuse of the stopped run, in `docs/quickstart-evidence-runbook.md`
- [X] T049 After T022, T029, T040, T041, T050, and T051 complete, run Terraform formatting, initialization without active remote backends, validation, native tests, TFLint, Checkov, policy tests, readiness tests, migration/live evidence-contract tests, state-contract tests, shell syntax, ShellCheck, and all existing repository tests through `Makefile`, correcting only feature-caused failures in the files named by the failing checks
- [X] T050 Add and test `terraform/bootstrap/backend.local.tf.example`, its ignored `terraform/bootstrap/backend.local.tf` active copy, explicit `/state/terraform-backend/<environment>/terraform.tfstate` initialization, discovery of the named active state and recognized backup files, mode-`0600` verification for every retained state artifact, mode-`0700` parent verification, content-free digest capture without state disclosure, retention until remote pull, lineage/resource-count equality, no-change, and locking succeed, replacement by the ignored AzureRM override only for `terraform init -migrate-state`, post-verification deletion, post-deletion absence checks for every named active/backup file, and an assertion that Terraform makes no underlying-media sanitization claim in `terraform/bootstrap/backend.local.tf.example`, `.gitignore`, and `tests/end-to-end/test_backend_state_contracts.py`
- [X] T051 Add automated secret-hygiene inspection for source, output schemas, bounded ordinary logs, approval/readiness/lifecycle evidence, and protected-artifact placement; assert that raw plans, state, state backups, credentials, tokens, keys, SAS values, and protected demo inputs never enter Git or `/evidence`, and inspect only controlled redacted representations without copying raw protected artifacts, in `tests/policy/test_backend_secret_hygiene.py` and `Makefile`
- [ ] T052 Execute the direct, unwrapped commands in `specs/003-terraform-backend-bootstrap/quickstart.md` in an approved Azure environment without any Bash/Python deployment driver; record the bootstrap approval, preliminary-readiness record, migration and final-readiness approval/evidence, dependent initialization and deployment approval, recovery record, separate unlock approval, and separate removal approval; assert bootstrap completion within 20 minutes excluding separately recorded role-propagation delay; assert replacement-operator recovery within 15 minutes; exercise digest-mismatch and stale-plan rejection; preserve only secret-free evidence; verify no state/plan/credential content entered Git or evidence; assert zero undocumented recovery commands and zero workflow substitutions; and record results in `/evidence/quickstart/<new-run-id>/backend-bootstrap/`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: Starts immediately.
- **Foundational (Phase 2)**: Starts after Setup and blocks all story implementation.
- **User Story 1 (Phase 3)**: Starts after Foundational and delivers the MVP backend.
- **User Story 2 (Phase 4)**: Depends on User Story 1 coordinates and backend.
- **User Story 3 (Phase 5)**: Depends on User Story 1 coordinates; it can proceed in parallel with
  User Story 2 after User Story 1 is complete.
- **User Story 4 (Phase 6)**: Depends on User Stories 2 and 3 because recovery and removal require
  initialized namespaces plus readiness/lifecycle evidence.
- **Polish (Phase 7)**: Depends on all selected stories. T049 depends on T022, T029, T040, T041,
  T050, and T051. T052 depends on successful completion of T049.

### User Story Dependency Graph

```text
Setup -> Foundational -> US1 (MVP)
                           | \
                           |  -> US3 --\
                           -> US2 ------> US4 -> Polish
```

### Within Each User Story

- Write the story's tests first and confirm they fail for the missing behavior.
- Implement validation and data contracts before resource composition or workflow integration.
- Keep Azure creation exclusively in direct pinned AVM calls.
- Keep readiness and lifecycle scripts read-only.
- Complete the story's independent test before beginning a dependent story.

## Parallel Opportunities

### User Story 1

After Foundational completes, run T006-T009 in parallel. After T012 defines names and mode
selection, T013-T015 can proceed in parallel in separate Terraform files. T017 and T018 can proceed
in parallel after their contracts are known.

### User Story 2

T021 and T022 can be written in parallel. T023 and T024 can be implemented in parallel. After the
migration contract exists, main and capacity-probe workflow changes in T026 and T027 can proceed in
parallel.

### User Story 3

T029-T031 can be written in parallel. After the readiness JSON behavior is implemented, native
main/probe gates T034-T035 and readiness examples T036-T037 can proceed in parallel.

### User Story 4

T040 and T041 can be written in parallel. Contract coverage T045 can proceed after lifecycle output
is defined while Terraform removal gates are being completed.

## Parallel Execution Examples

### User Story 1

```text
Task T006: naming.tftest.hcl
Task T007: managed-backend.tftest.hcl
Task T008: private-backend.tftest.hcl
Task T009: existing-backend.tftest.hcl
```

### User Story 2

```text
Task T023: terraform/backend.hcl.example
Task T024: terraform/capacity-probe/backend.hcl.example
```

### User Story 3

```text
Task T034: main-root readiness checks
Task T035: capacity-probe readiness checks
Task T036: main-root readiness example
Task T037: capacity-probe readiness example
```

### User Story 4

```text
Task T040: deterministic lifecycle tests
Task T041: opt-in live lifecycle acceptance
```

## Implementation Strategy

### MVP First: User Story 1

1. Complete Setup and Foundational phases.
2. Implement User Story 1 tests and bootstrap root.
3. Validate managed restricted-public mode first.
4. Validate private and existing modes.
5. Stop and review the MVP before adding dependent state initialization.

### Incremental Delivery

1. **US1**: Governed backend and non-secret coordinates.
2. **US2**: Protected migration, isolated state, and locking.
3. **US3**: Stable readiness evidence and pre-plan gates.
4. **US4**: Replacement-operator recovery and guarded removal.
5. **Polish**: Full quickstart acceptance and secret-free evidence.

### Execution Rules

- Never resume or reuse evidence run `20261013T164853Z`; create a new run ID for T052.
- Never put state, plans, state backups, credentials, access tokens, storage keys, SAS values, or
  protected application inputs in `/evidence`.
- Never use `terraform init -reconfigure` for a state migration.
- Never add custom Bash/Python readiness, lifecycle, resource-creating, provisioning, or
  apply-invoking behavior.
- Never unlock and destroy the managed backend in the same reviewed plan.
- Stop implementation if a required Azure resource cannot be composed through a published pinned
  AVM.

## Phase 8: Convergence

- [ ] T053 Add exact direct operator commands for remote no-change planning, native lock-conflict verification, migration-acceptance construction and schema validation, final readiness assertion construction, output-only plan review, post-generation approval, exact-plan apply, timing, and bounded evidence in `docs/quickstart-evidence-runbook.md`, with regression coverage in `tests/end-to-end/test_backend_state_contracts.py`, per FR-021, FR-030, FR-031, SC-008, T039, and T052 (partial)
- [ ] T054 Add exact direct replacement-operator commands for authentication timing, DNS/network checks, initialization, state reads, native lock acquisition/release in all three namespaces, bounded `backend-live-acceptance` construction, schema validation, and the 15-minute assertion in `docs/quickstart-evidence-runbook.md`, with contract regression coverage, per FR-028, FR-030, SC-005, SC-008, T046, and T052 (partial)
- [ ] T055 Restore the FR-027 fail-closed acceptance invariant by separating abandoned pre-migration cleanup from ordinary managed-backend removal and aligning lifecycle inputs, Terraform gates, schemas, tests, and operator documentation so acceptance removal cannot satisfy reverse migration with `state_migration_status = "never_migrated"`, per FR-027 and US4/AC4 (contradicts)
- [ ] T056 Implement and document the executable `reverse_migrated` managed-removal path, including protected local-state verification, separate unlock/destroy approvals and stale-plan rejection, backend absence, and complete schema-valid live-acceptance evidence, in the lifecycle contracts, Terraform tests, and `docs/quickstart-evidence-runbook.md`, per FR-027, FR-030, FR-031, SC-008, T046, and T052 (partial)
- [ ] T057 Execute one new direct, unwrapped, end-to-end live Azure acceptance run after T053-T056, covering managed creation, preliminary readiness, local-to-remote migration, final readiness, dependent initialization/deployment, replacement-operator recovery, reverse migration, separate unlock/removal approvals, stale-plan rejection, absence, timing limits, secret hygiene, zero undocumented commands, and zero workflow substitutions; retain only schema-valid secret-free evidence under a new run ID, per SC-001 through SC-008 and T052 (missing)
