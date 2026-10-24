---

description: "Implementation tasks for automated Chef bootstrap and convergence"
---

# Tasks: Automated Chef Bootstrap and Convergence

**Input**: Design documents from `/specs/005-automated-chef-bootstrap/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Required by the feature's clean-boot, fail-closed, retry, secret-hygiene, and
idempotency acceptance scenarios. Test tasks precede their corresponding implementation tasks.

**Organization**: Shared bootstrap foundations are followed by one phase per prioritized user
story. Live replacement and burst acceptance remain isolated in the final phase.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it changes a different file and has no incomplete dependency
- **[Story]**: Maps the task to a user story from `spec.md`
- Every task names the exact file it changes or validates

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish executable build/test surfaces for deterministic policy artifacts and
machine-validated contracts.

- [ ] T001 Create the feature contract and fixture test module covering every JSON schema under `specs/005-automated-chef-bootstrap/contracts/` in `tests/end-to-end/test_chef_bootstrap_contracts.py`
- [ ] T002 [P] Create the deterministic role-bundle builder CLI skeleton and protected output layout in `tests/end-to-end/build_chef_policy_bundles.sh`
- [ ] T003 [P] Pin role names, run lists, and cookbook sources for the existing CycleCloud and scheduler policies in `chef/policyfiles/cyclecloud.rb` and `chef/policyfiles/slurm.rb`
- [ ] T004 [P] Register the new contract test and Bash syntax check without changing existing validation order in `Makefile`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the common artifact, node-specification, bootstrap, state, and evidence
machinery required by both Linux roles.

**⚠️ CRITICAL**: No role-specific convergence begins until this phase is complete.

- [ ] T005 Add failing deterministic-build tests in `tests/end-to-end/test_chef_bootstrap_contracts.py` requiring identical source trees to produce identical SHA-256 values, a decoded custom-data document no larger than `60000` bytes, manifest `sourceRevision` matching `^[0-9a-f]{40}$`, and every artifact digest matching `^[0-9a-f]{64}$`
- [ ] T006 Implement normalized owner/group, timestamps, path ordering, role separation, manifest canonicalization, SHA-256 recording, and the `60000`-byte custom-data gate in `tests/end-to-end/build_chef_policy_bundles.sh`
- [ ] T007 Add failing common bootstrap tests for exact Chef `18.11.11`, RPM SHA-256 `d68c339bc85ded67b793de4e20f35886c5fbd9b5a9e95dabbe5ede6211b01365`, pre-extraction verification, immutable release directories, atomic `current` switching, and secret-free failure output in `tests/end-to-end/test_chef_bootstrap_contracts.py`
- [ ] T008 Refactor `chef/bootstrap/linux.sh` to verify/install exact Chef Infra Client `18.11.11`, validate the directly delivered role bundle and node specification before extraction, stage `/opt/slurm-demo/releases/<policy-sha256>`, and atomically select `/opt/slurm-demo/current`
- [ ] T009 Add failing state-machine tests in `tests/end-to-end/test_chef_bootstrap_contracts.py` for states `environment_ready`, `waiting_dependencies`, `converging`, `failed_retryable`, `replacement_required`, `converged`, and `idempotency_verified`, with initial attempts limited to integers `1` and `2` and retries requiring identical manifest/specification digests
- [ ] T010 Implement atomic state/evidence validation, role locking, bounded failure codes, attempt preservation, and replacement-required enforcement in `chef/bin/convergence_state.py`
- [ ] T011 Define common non-secret node-specification values in `terraform/locals.tf` and `terraform/variables.tf`, requiring cluster `cross-region-demo`, Slurm UID/GID `11100`, Munge UID/GID `11101`, and `hpcuser01` UID/GID `11200` with home `/shared/home/hpcuser01`
- [ ] T012 Add Terraform tests that reject secrets, mutable versions, role/specification mismatches, and oversized rendered custom data in `terraform/tests/chef-bootstrap.tftest.hcl`

**Checkpoint**: Both roles can consume the same deterministic artifact/state contracts without
performing role-specific configuration.

---

## Phase 3: User Story 1 - Receive a Ready CycleCloud Appliance (Priority: P1) 🎯 MVP

**Goal**: A newly rebuilt CycleCloud appliance completes first-run, verifies its pinned policy and
Slurm project, converges automatically, and imports exactly one approved cluster.

**Independent Test**: Build and render only the CycleCloud payload, run unit/failure fixtures, then
rebuild the CycleCloud VM without interactive repair and require `converged`, the managed-identity
provider, and exactly one `cross-region-demo` cluster.

### Tests for User Story 1

- [ ] T013 [US1] Add failing ChefSpec examples for exact CycleCloud `8.9.3`, Slurm project `4.0.11`, project/install artifact digests, provider readiness, validated headless transformation, and exactly one cluster import in `chef/cookbooks/cyclecloud_node/spec/unit/recipes/default_spec.rb`
- [ ] T014 [P] [US1] Add failing bootstrap-order, digest-mismatch, cleanup, reboot, and no-secret-output tests for first-run followed by Chef convergence in `tests/end-to-end/test_cyclecloud_stack.py`
- [ ] T015 [P] [US1] Add failing wrapper tests for lock contention, attempt-1 retryability, attempt-2 replacement requirement, manifest/specification binding, and converged evidence in `tests/end-to-end/test_chef_bootstrap_contracts.py`
- [ ] T016 [P] [US1] Extend CycleCloud InSpec controls for staged manifest/specification permissions, Chef version, Slurm project version, cluster import, bounded state, and temporary-secret absence in `chef/test/integration/cyclecloud/controls/default.rb`

### Implementation for User Story 1

- [ ] T017 [US1] Download and verify `azure-slurm-pkg-4.0.11.tar.gz` SHA-256 `f85a1d016eca3786eb9845fcbffcefaf674bfcd4b59738597e90877047a23e36`, install the project idempotently, and reject version skew in `chef/cookbooks/cyclecloud_node/recipes/default.rb`
- [ ] T018 [US1] Install the repository `headless-template` tool from the staged policy, generate a separate candidate template, validate it before atomic replacement, and preserve the last valid output in `chef/cookbooks/cyclecloud_node/recipes/default.rb`
- [ ] T019 [US1] Bind provider verification, project installation, template transformation, cluster properties, and exactly-one-cluster import to explicit idempotent resources in `chef/cookbooks/cyclecloud_node/recipes/default.rb` and `chef/cookbooks/cyclecloud_node/templates/default/cluster.properties.erb`
- [ ] T020 [US1] Refactor `chef/bin/converge-cyclecloud.sh` to use `/opt/slurm-demo/current`, validate manifest/specification digests, serialize execution, invoke Chef Local, remove temporary protected files, and write schema-valid state/evidence
- [ ] T021 [US1] Extend `infra/cyclecloud/bootstrap.sh` to decode and verify the CycleCloud role bundle/specification, complete the existing CycleCloud 8.9.3 first-run exception, invoke initial Chef convergence automatically, and keep readiness false on any downstream failure
- [ ] T022 [US1] Add role bundle, manifest, specification, and digest parameters with decoded-size validation to `infra/cyclecloud/main.bicep`
- [ ] T023 [US1] Render and pass the non-secret CycleCloud policy payload through the existing VM-stack boundary without adding Azure resources in `terraform/cyclecloud-platform.tf` and `tests/end-to-end/cyclecloud_stack.sh`
- [ ] T024 [US1] Update CycleCloud attributes and templates to consume only validated node-specification values and immutable release paths in `chef/cookbooks/cyclecloud_node/attributes/default.rb` and `chef/cookbooks/cyclecloud_node/templates/default/slurm-headless-overrides.txt.erb`

**Checkpoint**: CycleCloud clean boot is independently complete and scheduler dispatch remains
unnecessary for this story.

---

## Phase 4: User Story 2 - Prepare a Dependency-Aware Scheduler (Priority: P2)

**Goal**: Scheduler first boot stages a complete verified environment without partial Slurm
configuration; the governed workflow converges it only after CycleCloud, secret-access, and
identity gates pass.

**Independent Test**: Boot the scheduler before its dependencies, require
`waiting_dependencies` and no partial services/configuration, then dispatch one governed
convergence and require Slurm/Munge/NFS, supported `azslurm`, and reconciled `hpcuser01`.

### Tests for User Story 2

- [ ] T025 [US2] Add failing Terraform tests for scheduler custom-data staging, no autonomous convergence, Key Vault `Secrets User` least privilege, no secret values, and unchanged zero-public-IP posture in `terraform/tests/chef-bootstrap.tftest.hcl`
- [ ] T026 [P] [US2] Add failing ChefSpec examples for Slurm/Munge UID/GID `11100`/`11101`, `hpcuser01` UID/GID `11200`, `/shared/home/hpcuser01`, Ed25519 key preservation, NFS, direct peering, one-node limit, and release `4.0.11` in `chef/cookbooks/slurm_scheduler/spec/unit/recipes/default_spec.rb`
- [ ] T027 [P] [US2] Add failing managed-identity Key Vault REST tests for token scope, user-assigned client ID, private vault URI, mode-`0600` temporary output, redaction, and unconditional cleanup in `tests/end-to-end/test_chef_bootstrap_contracts.py`
- [ ] T028 [P] [US2] Add failing governed-dispatch tests for CycleCloud receipt, scheduler environment receipt, secret-access gate, no-secret Run Command payload, public-key handoff, and downstream blocking in `tests/end-to-end/test_converge_linux_roles.py`

### Implementation for User Story 2

- [ ] T029 [US2] Grant only the scheduler user-assigned identity Key Vault secret-read data-plane access through the existing pinned AVM role-assignment interface in `terraform/security.tf`
- [ ] T030 [US2] Render the verified scheduler role bundle/specification into first-boot custom data, stage only, and write `waiting_dependencies` without polling or starting Slurm convergence in `terraform/compute.tf`
- [ ] T031 [US2] Implement IMDS token acquisition and private Key Vault REST retrieval with protected temporary output, explicit failures, and no Azure CLI dependency in `chef/bin/retrieve-key-vault-secret.py`
- [ ] T032 [US2] Refactor `chef/bin/converge-scheduler.sh` to require a governed authorization receipt, retrieve `cyclecloud-admin-password` at runtime, invoke release-matched `azslurm initconfig` once under root-only trace-disabled controls, and clean every temporary credential path
- [ ] T033 [US2] Replace `slurmdemo` with Chef-managed `hpcuser01` group/user UID/GID `11200`, shared home `/shared/home/hpcuser01`, and generate-or-preserve mode-`0600` Ed25519 keys without direct account-database edits in `chef/cookbooks/slurm_scheduler/recipes/demo_user.rb`
- [ ] T034 [US2] Download and verify `azure-slurm-install-pkg-4.0.11.tar.gz` SHA-256 `a489f4c5ec2404dc02a09792af5f32f4683e164327d89c4c2dfc8d9a30402482`, configure Slurm/Munge/NFS, and start services only after validation in `chef/cookbooks/slurm_scheduler/recipes/default.rb`
- [ ] T035 [US2] Replace unsupported credential assumptions with release-matched generated configuration and protected file modes in `chef/cookbooks/slurm_scheduler/templates/default/azslurm.conf.erb` and `chef/cookbooks/slurm_scheduler/templates/default/slurm.conf.erb`
- [ ] T036 [US2] Implement ordered dependency inspection, authorization receipt creation, Azure VM Run Command dispatch, bounded output collection, and nonzero downstream blocking in `tests/end-to-end/converge_linux_roles.sh`
- [ ] T037 [US2] Implement an idempotent CycleCloud 8.9.3 application-import reconciliation for non-superuser `hpcuser01`, UID/GID `11200`, public key, and `cross-region-demo` access in `chef/bin/reconcile-cyclecloud-user.sh`
- [ ] T038 [US2] Add scheduler public-key validation/fingerprinting, CycleCloud reconciliation dispatch, and an `hpc-user` dependency receipt without private-key transfer in `tests/end-to-end/converge_linux_roles.sh`
- [ ] T039 [P] [US2] Extend scheduler InSpec controls for identities, shared home, key modes, packages, NFS exports, private CycleCloud integration, services, staged contracts, and secret cleanup in `chef/test/integration/scheduler/controls/default.rb`
- [ ] T040 [US2] Add scheduler bundle/specification outputs and secret-free dependency receipt references required by the governed workflow in `terraform/outputs.tf`

**Checkpoint**: Both persistent Linux roles converge through governed entry points, and burst-node
creation remains blocked until `hpcuser01` reconciliation succeeds.

---

## Phase 5: User Story 3 - Reproduce and Audit Convergence (Priority: P3)

**Goal**: Reviewers can prove exact inputs, cleanup, bounded retry behavior, and zero-update second
runs without exposing credentials.

**Independent Test**: Validate both role evidence records, rerun both unchanged roles, require zero
updated resources, inject first/second failures, and prove retry versus replacement transitions
while all secret scans remain clean.

### Tests for User Story 3

- [ ] T041 [US3] Add failing evidence-contract tests requiring source revision, manifest/specification digests, Chef `18.11.11`, Slurm `4.0.11`, timestamps, result/state, update count, dependency receipts, cleanup proof, and no additional properties in `tests/end-to-end/test_chef_bootstrap_contracts.py`
- [ ] T042 [P] [US3] Add failing retry/failure-injection tests proving one identical-input retry, preserved attempt evidence, changed-input rejection, and `replacement_required` after the second failure in `tests/end-to-end/test_converge_linux_roles.py`
- [ ] T043 [P] [US3] Extend the idempotency verifier to fail on any nonzero updated-resource count or altered staged digest in `chef/test/integration/idempotency/verify.sh`
- [ ] T044 [P] [US3] Extend secret-hygiene policy tests for manifests, specifications, state, evidence, Run Command output, temporary paths, passwords, tokens, private keys, and reversible derivatives in `tests/policy/test_backend_secret_hygiene.py`

### Implementation for User Story 3

- [ ] T045 [US3] Emit schema-valid per-attempt and idempotency evidence atomically while preserving prior attempts and excluding command lines/protected values in `chef/bin/convergence_state.py`
- [ ] T046 [US3] Add `initial`, `retry`, `update`, and `verify-idempotency` operation enforcement, identical-input retry checks, second-failure blocking, and separate zero-update receipts in `tests/end-to-end/converge_linux_roles.sh`
- [ ] T047 [US3] Add both wrappers' explicit idempotency mode, Chef updated-resource parsing, staged digest revalidation, cleanup proof, and zero-update failure handling in `chef/bin/converge-cyclecloud.sh` and `chef/bin/converge-scheduler.sh`
- [ ] T048 [US3] Document state inspection, dependency transitions, protected dispatch, safe reruns, replacement-required recovery, public-key reconciliation, and evidence transfer in `docs/quickstart-evidence-runbook.md`

**Checkpoint**: The same approved inputs are reproducible, auditable, fail closed, and idempotent.

---

## Phase 6: Polish & Governed Acceptance

**Purpose**: Complete validation, live clean-boot evidence, bounded burst acceptance, and final
no-change proof without weakening existing approval gates.

- [ ] T049 Register new Python, Bash, Terraform, ChefSpec, contract, and governed-workflow tests in `Makefile`
- [ ] T050 [P] Run contract, Terraform, ChefSpec, Cookstyle, InSpec fixture, secret-hygiene, and full `make validate` checks and record only secret-free results in `specs/005-automated-chef-bootstrap/quickstart.md`
- [ ] T051 Generate feature 004 credentials in a new protected evidence run, complete its deferred `windowsadmin`/`hpcadmin` login acceptance, and record only pass/fail labels through `docs/quickstart-evidence-runbook.md`
- [ ] T052 Produce reviewed Terraform plan and Bicep what-if evidence, obtain required approvals, and perform an untouched CycleCloud VM-only clean rebuild using `tests/end-to-end/cyclecloud_stack.sh`
- [ ] T053 Rebuild/stage the scheduler through the approved Terraform plan, dispatch governed scheduler convergence, reconcile `hpcuser01`, and capture both zero-update second runs through `tests/end-to-end/converge_linux_roles.sh`
- [ ] T054 Submit the bounded one-node burst job as `hpcuser01`, verify matching UID/GID/shared-home behavior and clean node termination, then produce the final no-change plan through `docs/quickstart-evidence-runbook.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: Starts from commits `d4cbea1` and `591e66b`.
- **Phase 2 (Foundational)**: Depends on Phase 1 and blocks all user stories.
- **Phase 3 (US1)**: Depends on the common artifact/bootstrap/state foundation.
- **Phase 4 (US2)**: Depends on US1 because scheduler dispatch requires a converged CycleCloud
  receipt and imported cluster.
- **Phase 5 (US3)**: Depends on US1 and US2 because it verifies both completed role workflows.
- **Phase 6 (Acceptance)**: Depends on all source implementation and explicit deployment approvals.

### User Story Dependency Graph

```text
Setup -> Foundation -> US1 CycleCloud -> US2 Scheduler -> US3 Audit -> Governed Acceptance
```

### Within Each User Story

- Write each listed test first and confirm it fails for the intended missing behavior.
- Validate artifacts/specifications before installation or Chef execution.
- Complete role-local behavior before governed cross-role orchestration.
- Preserve failed-attempt evidence and remove temporary protected values on every exit path.
- Require each story's independent test before advancing to the next story.

### Parallel Opportunities

- T002, T003, and T004 can proceed in parallel after T001 defines the shared test surface.
- T014, T015, and T016 can proceed in parallel after the US1 contracts are fixed.
- T026, T027, and T028 can proceed in parallel after the scheduler specification is rendered.
- T039 can proceed in parallel with governed workflow implementation after scheduler outcomes are
  fixed.
- T042, T043, and T044 can proceed in parallel after both wrappers have stable interfaces.
- T050 can prepare static validation evidence independently of live approval tasks T051-T054.

---

## Parallel Example: User Story 1

```text
Task T014: Add CycleCloud bootstrap-order and cleanup tests in tests/end-to-end/test_cyclecloud_stack.py
Task T015: Add CycleCloud wrapper state/retry tests in tests/end-to-end/test_chef_bootstrap_contracts.py
Task T016: Add CycleCloud live outcome controls in chef/test/integration/cyclecloud/controls/default.rb
```

## Parallel Example: User Story 2

```text
Task T026: Add scheduler ChefSpec identity/package tests
Task T027: Add managed-identity Key Vault REST tests
Task T028: Add governed scheduler dispatch/public-key handoff tests
```

## Parallel Example: User Story 3

```text
Task T042: Add governed retry and replacement tests
Task T043: Extend role idempotency verification
Task T044: Extend secret-hygiene policy coverage
```

---

## Implementation Strategy

### MVP First: User Story 1

1. Complete Setup and Foundational phases.
2. Complete T013-T024.
3. Stop and validate the CycleCloud role using fixtures before any live rebuild.
4. With approval, demonstrate one untouched CycleCloud clean boot independently.

### Incremental Delivery

1. **Foundation**: Deterministic role artifacts, exact package pins, node specifications, and
   bounded state/evidence.
2. **US1**: Automatic CycleCloud first-run plus initial Chef convergence and cluster import.
3. **US2**: Dependency-gated scheduler convergence and `hpcuser01` reconciliation.
4. **US3**: Retry, audit, cleanup, and zero-update verification across both roles.
5. **Acceptance**: New feature 004 credentials, clean rebuilds, one-node burst, and no-change plan.

### Completion Gate

- All 54 tasks are checked.
- Feature 004's deferred live login acceptance is closed by the new evidence run.
- Both role manifests/specifications match approved digests.
- Both second convergences report zero resources updated.
- The bounded burst job succeeds as `hpcuser01`.
- Secret scans and the final Terraform no-change plan pass.
