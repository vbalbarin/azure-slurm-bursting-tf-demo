---

description: "Implementation tasks for automated Chef bootstrap and convergence"
---

# Tasks: Automated Chef Bootstrap and Convergence

**Input**: Design documents from `/specs/005-automated-chef-bootstrap/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`,
`quickstart.md`

**Tests**: Required by the feature's clean-boot, fail-closed, retry, reboot, secret-hygiene,
state-timing, and idempotency acceptance scenarios. Test tasks precede their implementations.

**Organization**: Shared bootstrap foundations are followed by one phase per prioritized user
story. Live credential deployment, manual CycleCloud UI work, VM replacement, and burst acceptance
remain isolated in the final phase.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it changes a different file and has no incomplete dependency.
- **[Story]**: Maps the task to a user story from `spec.md`.
- Every task names the exact file it changes or validates.

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish executable contract, policy-lock, bundle-build, and test surfaces.

- [X] T001 Create the CycleCloud UI-gate attestation schema with `schemaVersion` exactly `1`, `userName` exactly `hpcuser01`, `superuser` exactly `false`, `nodeAccessEnabled` exactly `true`, UID exactly `11200`, cluster exactly `cross-region-demo`, permission exactly `node-user`, matching fingerprint/source revision/specification digest/identity-receipt digest, password disposition `not-required` or `force-reset-discarded`, operator/timestamp, and accepted/rejected result in `specs/005-automated-chef-bootstrap/contracts/cyclecloud-user-attestation.schema.json`
- [X] T002 Create the feature contract and fixture test module covering every JSON schema under `specs/005-automated-chef-bootstrap/contracts/` in `tests/end-to-end/test_chef_bootstrap_contracts.py`
- [X] T003 [P] Create the deterministic role-bundle builder CLI skeleton and protected output layout in `tests/end-to-end/build_chef_policy_bundles.sh`
- [X] T004 [P] Pin role names, run lists, and cookbook sources in `chef/policyfiles/cyclecloud.rb` and `chef/policyfiles/slurm.rb`
- [X] T005 [P] Register the initial contract test and Bash syntax check without changing existing validation order in `Makefile`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Build the common immutable policy, artifact, bootstrap, state, and specification
machinery required by both Linux roles.

**CRITICAL**: No role-specific convergence begins until this phase is complete.

- [X] T006 Add failing Policyfile-lock tests requiring role-specific lock files, a 64-character lock `revision_id`, matching manifest `policyRevision`, matching `policyLockSha256`, and failure when cookbook source changes without lock regeneration in `tests/end-to-end/test_chef_bootstrap_contracts.py`
- [X] T007 Generate reviewed immutable locks and implement pinned lock generation/verification in `chef/policyfiles/cyclecloud.lock.json`, `chef/policyfiles/slurm.lock.json`, and `tests/end-to-end/build_chef_policy_bundles.sh`
- [X] T008 Add failing deterministic-build tests requiring identical source trees and locks to produce identical SHA-256 values, decoded custom data no larger than `60000` bytes, manifest `sourceRevision` matching `^[0-9a-f]{40}$`, and artifact digests matching `^[0-9a-f]{64}$` in `tests/end-to-end/test_chef_bootstrap_contracts.py`
- [X] T009 Implement normalized owner/group, timestamps, path ordering, role separation, lock inclusion, manifest canonicalization, SHA-256 recording, and the `60000`-byte custom-data gate in `tests/end-to-end/build_chef_policy_bundles.sh`
- [X] T010 Add failing common bootstrap tests for Chef `18.11.11`, RPM SHA-256 `d68c339bc85ded67b793de4e20f35886c5fbd9b5a9e95dabbe5ede6211b01365`, lock/digest verification before extraction, immutable releases, atomic `current` switching, and secret-free failures in `tests/end-to-end/test_chef_bootstrap_contracts.py`
- [X] T011 Refactor common bootstrap to verify/install Chef `18.11.11`, validate the bundle, Policyfile lock, manifest, and node specification, stage `/opt/slurm-demo/releases/<policy-sha256>`, and atomically select `/opt/slurm-demo/current` in `chef/bootstrap/linux.sh`
- [X] T012 Add failing state-machine tests for `environment_ready`, `waiting_dependencies`, `converging`, `failed_retryable`, `replacement_required`, `converged`, and `idempotency_verified`, attempts limited to `1` and `2`, and identical manifest/specification digests on retry in `tests/end-to-end/test_chef_bootstrap_contracts.py`
- [X] T013 Implement atomic state/evidence validation, role locking, bounded failure codes, attempt preservation, and replacement-required enforcement in `chef/bin/convergence_state.py`
- [X] T014 [P] Define common non-secret node-specification values requiring cluster `cross-region-demo`, Slurm UID/GID `11100`, Munge UID/GID `11101`, and `hpcuser01` UID/GID `11200` with home `/shared/home/hpcuser01` in `terraform/locals.tf` and `terraform/variables.tf`
- [X] T015 [P] Add Terraform tests rejecting secrets, mutable versions, role/specification mismatches, missing lock identities, and oversized rendered custom data in `terraform/tests/chef-bootstrap.tftest.hcl`

**Checkpoint**: Both roles can consume deterministic, lock-bound artifact/state contracts without
performing role-specific configuration.

---

## Phase 3: User Story 1 - Receive a Ready CycleCloud Appliance (Priority: P1) MVP

**Goal**: A new CycleCloud appliance completes first-run, verifies its pinned policy and Slurm
project, converges automatically, and imports exactly one approved cluster.

**Independent Test**: Build and render only the CycleCloud payload, run unit/failure fixtures, then
rebuild the CycleCloud VM without interactive repair and require `converged`, the managed-identity
provider, and exactly one `cross-region-demo` cluster.

### Tests for User Story 1

- [X] T016 [US1] Add failing ChefSpec examples for CycleCloud `8.9.3`, Slurm project `4.0.11`, project/install artifact digests, provider readiness, validated headless transformation, and exactly one cluster import in `chef/cookbooks/cyclecloud_node/spec/unit/recipes/default_spec.rb`
- [X] T017 [P] [US1] Add failing bootstrap-order, digest-mismatch, cleanup, reboot-without-reimport, and no-secret-output tests for first-run followed by Chef convergence in `tests/end-to-end/test_cyclecloud_stack.py`
- [X] T018 [P] [US1] Add failing wrapper tests for lock contention, attempt-1 retryability, attempt-2 replacement requirement, lock/manifest/specification binding, and converged evidence in `tests/end-to-end/test_chef_bootstrap_contracts.py`
- [X] T019 [P] [US1] Extend CycleCloud InSpec controls for staged lock/manifest/specification permissions, Chef version, Slurm project version, cluster import, bounded state, and temporary-secret absence in `chef/test/integration/cyclecloud/controls/default.rb`

### Implementation for User Story 1

- [X] T020 [US1] Download and verify `azure-slurm-pkg-4.0.11.tar.gz` SHA-256 `f85a1d016eca3786eb9845fcbffcefaf674bfcd4b59738597e90877047a23e36`, install it idempotently, and reject version skew in `chef/cookbooks/cyclecloud_node/recipes/default.rb`
- [X] T021 [US1] Install the staged `headless-template` tool, generate a separate candidate, validate it before atomic replacement, and preserve the last valid template in `chef/cookbooks/cyclecloud_node/recipes/default.rb`
- [X] T022 [US1] Bind provider verification, project installation, template transformation, cluster properties, and exactly-one-cluster import to explicit idempotent resources in `chef/cookbooks/cyclecloud_node/recipes/default.rb` and `chef/cookbooks/cyclecloud_node/templates/default/cluster.properties.erb`
- [X] T023 [US1] Refactor the wrapper to validate lock/manifest/specification digests, serialize execution, invoke Chef Local from `/opt/slurm-demo/current`, clean temporary protected files, and write schema-valid state/evidence in `chef/bin/converge-cyclecloud.sh`
- [X] T024 [US1] Extend first boot to verify the CycleCloud bundle/specification, complete the CycleCloud 8.9.3 first-run exception, invoke initial Chef convergence, and keep readiness false on downstream failure in `infra/cyclecloud/bootstrap.sh`
- [X] T025 [US1] Add role bundle, manifest, specification, lock identity, and digest parameters with decoded-size validation in `infra/cyclecloud/main.bicep`
- [X] T026 [US1] Render and pass the non-secret CycleCloud payload through the existing VM-stack boundary without adding Azure resources in `terraform/cyclecloud-platform.tf` and `tests/end-to-end/cyclecloud_stack.sh`
- [X] T027 [US1] Consume only validated node-specification values and immutable release paths in `chef/cookbooks/cyclecloud_node/attributes/default.rb` and `chef/cookbooks/cyclecloud_node/templates/default/slurm-headless-overrides.txt.erb`
- [X] T028 [US1] Run the CycleCloud ChefSpec, wrapper, bootstrap-stack, and InSpec fixture tests and record their secret-free expected outcomes in `specs/005-automated-chef-bootstrap/quickstart.md`

**Checkpoint**: CycleCloud clean boot is independently complete; scheduler dispatch and the manual
user gate remain unnecessary for this story.

---

## Phase 4: User Story 2 - Prepare a Dependency-Aware Scheduler (Priority: P2)

**Goal**: Scheduler first boot stages verified content without partial Slurm changes, governed
dispatch completes convergence after dependencies pass, and a public-identity receipt plus supported
manual CycleCloud UI gate authorizes burst acceptance.

**Independent Test**: Boot a scheduler before CycleCloud is ready, require `waiting_dependencies`
with no partial services, satisfy dependencies, converge once, produce a value-free `hpcuser01`
receipt, reject malformed UI attestations, and accept the exact supported UI-gate outcome.

### Tests for User Story 2

- [X] T029 [US2] Add failing Terraform tests for scheduler custom-data staging, no autonomous convergence, Key Vault `Secrets User` least privilege, no secret values, and unchanged zero-public-IP posture in `terraform/tests/chef-bootstrap.tftest.hcl`
- [X] T030 [P] [US2] Add failing ChefSpec examples for Slurm/Munge UID/GID `11100`/`11101`, `hpcuser01` UID/GID `11200`, `/shared/home/hpcuser01`, Ed25519 key preservation, NFS, direct peering, one-node limit, and release `4.0.11` in `chef/cookbooks/slurm_scheduler/spec/unit/recipes/default_spec.rb`
- [X] T031 [P] [US2] Add failing managed-identity Key Vault REST tests for token scope, user-assigned client ID, private vault URI, mode-`0600` temporary output, redaction, and unconditional cleanup in `tests/end-to-end/test_chef_bootstrap_contracts.py`
- [X] T032 [P] [US2] Add failing governed-dispatch tests for CycleCloud/scheduler receipts, secret-access gate, no-secret Run Command payloads, canonical public-identity receipt digests, UI-attestation source/specification/receipt binding, one-time-password disposition, unsupported-interface rejection, and downstream blocking in `tests/end-to-end/test_converge_linux_roles.py`
- [X] T033 [P] [US2] Add failing remote state-inspection tests requiring schema-valid CycleCloud and scheduler state within less than `60` seconds from invocation in `tests/end-to-end/test_converge_linux_roles.py`
- [X] T034 [P] [US2] Add failing scheduler reboot tests proving no credential rotation, policy application, convergence-attempt increment, or autonomous Slurm convergence in `tests/end-to-end/test_scheduler_bootstrap.py`

### Implementation for User Story 2

- [X] T035 [US2] Grant only the scheduler user-assigned identity Key Vault secret-read data-plane access through the existing pinned AVM role-assignment interface in `terraform/security.tf`
- [X] T036 [US2] Render the verified scheduler lock/bundle/specification into first-boot custom data, stage only, and write `waiting_dependencies` without polling or starting convergence in `terraform/compute.tf`
- [X] T037 [US2] Implement IMDS token acquisition and private Key Vault REST retrieval with protected temporary output, explicit failures, and no Azure CLI dependency in `chef/bin/retrieve-key-vault-secret.py`
- [X] T038 [US2] Require a governed authorization receipt, retrieve `cyclecloud-admin-password` at runtime, invoke release-matched `azslurm initconfig` once under root-only trace-disabled controls, and clean every temporary credential path in `chef/bin/converge-scheduler.sh`
- [X] T039 [US2] Replace `slurmdemo` with Chef-managed `hpcuser01` group/user UID/GID `11200`, home `/shared/home/hpcuser01`, and generate-or-preserve mode-`0600` Ed25519 keys without direct account-database edits in `chef/cookbooks/slurm_scheduler/recipes/demo_user.rb`
- [X] T040 [US2] Download and verify `azure-slurm-install-pkg-4.0.11.tar.gz` SHA-256 `a489f4c5ec2404dc02a09792af5f32f4683e164327d89c4c2dfc8d9a30402482`, configure Slurm/Munge/NFS, and start services only after validation in `chef/cookbooks/slurm_scheduler/recipes/default.rb`
- [X] T041 [US2] Replace unsupported credential assumptions with release-matched generated configuration and protected modes in `chef/cookbooks/slurm_scheduler/templates/default/azslurm.conf.erb` and `chef/cookbooks/slurm_scheduler/templates/default/slurm.conf.erb`
- [X] T042 [US2] Implement ordered dependency inspection, authorization receipt creation, Azure VM Run Command dispatch, bounded output collection, and nonzero downstream blocking in `tests/end-to-end/converge_linux_roles.sh`
- [X] T043 [US2] Validate `hpcuser01` name exactly, UID/GID exactly `11200`, home exactly `/shared/home/hpcuser01`, one Ed25519 public key, derived SHA-256 fingerprint, source revision, and specification digest before emitting a canonical value-free receipt with its own SHA-256 digest in `chef/bin/publish-hpc-user-receipt.sh`
- [X] T044 [US2] Validate the manual CycleCloud UI attestation against the current scheduler source revision, specification digest, identity-receipt digest, and fingerprint; require non-superuser cluster-scoped `node-user` access and accepted password disposition; reject stale/overprivileged/mismatched records; and block burst dispatch without undocumented APIs in `tests/end-to-end/converge_linux_roles.sh`
- [X] T045 [P] [US2] Extend scheduler InSpec controls for identities, shared home, key modes, packages, NFS exports, private CycleCloud integration, services, staged contracts, and secret cleanup in `chef/test/integration/scheduler/controls/default.rb`
- [X] T046 [US2] Add scheduler bundle/specification outputs and secret-free dependency/public-identity receipt references required by governed dispatch in `terraform/outputs.tf`

**Checkpoint**: Both persistent roles converge through governed entry points, and burst-node
creation remains blocked until the supported manual CycleCloud UI attestation is accepted.

---

## Phase 5: User Story 3 - Reproduce and Audit Convergence (Priority: P3)

**Goal**: Reviewers can prove exact lock-bound inputs, cleanup, bounded retry and reboot behavior,
sub-minute state inspection, and zero-update second runs without exposing credentials.

**Independent Test**: Validate both evidence records, rerun unchanged roles, require zero updates,
measure both state queries below 60 seconds, inject first/second failures, and verify retry versus
replacement transitions while secret scans remain clean.

### Tests for User Story 3

- [X] T047 [US3] Add failing evidence-contract tests requiring source revision, manifest/specification digests, Policyfile lock revision/digest, Chef `18.11.11`, Slurm `4.0.11`, timestamps, result/state, update count, dependency receipts, cleanup proof, and no additional properties in `tests/end-to-end/test_chef_bootstrap_contracts.py`
- [X] T048 [P] [US3] Add failing retry/update/failure-injection tests proving one identical-input retry, preserved attempt evidence, changed-input retry rejection, approved existing-VM release staging, atomic `current` switching, prior-release restoration on update failure, and `replacement_required` after the second initial failure in `tests/end-to-end/test_converge_linux_roles.py`
- [X] T049 [P] [US3] Extend the idempotency verifier to fail on any nonzero updated-resource count or altered staged lock/artifact digest in `chef/test/integration/idempotency/verify.sh`
- [X] T050 [P] [US3] Extend secret-hygiene policy tests for manifests, specifications, UI attestations, state, evidence, Run Command output, temporary paths, passwords, tokens, private keys, and reversible derivatives in `tests/policy/test_backend_secret_hygiene.py`

### Implementation for User Story 3

- [X] T051 [US3] Emit schema-valid per-attempt and idempotency evidence atomically while preserving prior attempts and excluding command lines/protected values in `chef/bin/convergence_state.py`
- [X] T052 [US3] Enforce `initial`, `retry`, `update`, and `verify-idempotency` operations; for `update`, validate and transfer the newly approved non-secret lock/manifest/specification/bundle payload, request side-by-side immutable staging, and retain separate update evidence in `tests/end-to-end/converge_linux_roles.sh`
- [X] T053 [US3] Add explicit update/idempotency modes, atomic `current` switching with prior-release restoration on failed updates, Chef updated-resource parsing, lock/artifact digest revalidation, cleanup proof, and zero-update failure handling in `chef/bin/converge-cyclecloud.sh` and `chef/bin/converge-scheduler.sh`
- [X] T054 [US3] Implement bounded remote state inspection with a hard timeout below `60` seconds and schema validation for both persistent VMs in `tests/end-to-end/converge_linux_roles.sh`
- [X] T055 [US3] Add governed before/after reboot evidence comparison for state digests, convergence attempts, credentials, cluster count, and explicit-policy-only behavior in `tests/end-to-end/converge_linux_roles.sh`
- [X] T056 [US3] Document state inspection, dependency transitions, protected dispatch, safe reruns, replacement recovery, public-identity receipt, manual UI gate, reboot proof, and evidence transfer in `docs/quickstart-evidence-runbook.md`

**Checkpoint**: The same approved inputs are reproducible, auditable, reboot-safe, fail closed, and
idempotent.

---

## Phase 6: Polish & Governed Acceptance

**Purpose**: Complete static validation, deploy new credentials before testing them, perform clean
rebuilds, execute the supported manual UI gate, and capture bounded burst/no-change evidence.

- [X] T057 Register all new Python, Bash, Terraform, ChefSpec, contract, state-timing, reboot, UI-attestation, and governed-workflow tests in `Makefile`
- [ ] T058 Run contract, Terraform, Bicep, Python, ShellCheck, ChefSpec, Cookstyle, InSpec fixture, secret-hygiene, and full `make validate` checks and record only secret-free expected results in `specs/005-automated-chef-bootstrap/quickstart.md`
- [ ] T059 Generate feature 004 credentials in a new protected evidence context without attempting login against existing VMs, and retain only protected values plus the accepted value-free receipt through `docs/quickstart-evidence-runbook.md`
- [ ] T060 Produce reviewed Terraform plan and CycleCloud Bicep what-if evidence from the approved commit, bind approval to exact digests, and record approvals in `docs/quickstart-evidence-runbook.md`
- [ ] T061 Apply only the approved Terraform plan and CycleCloud stack artifact, rebuild the Terraform-owned Windows jump host and Bicep-owned CycleCloud appliance, rebuild the Terraform-owned scheduler for its approved custom data, and record deployment evidence through `tests/end-to-end/cyclecloud_stack.sh` and `docs/quickstart-evidence-runbook.md`
- [ ] T062 After T061 deploys the new credentials, complete feature 004's deferred `windowsadmin` and `hpcadmin` login checks and record only pass/fail labels in `docs/quickstart-evidence-runbook.md`
- [ ] T063 Validate untouched CycleCloud clean boot, exactly one imported cluster, secret cleanup, and schema-valid remote state in less than `60` seconds through `tests/end-to-end/cyclecloud_stack.sh`
- [ ] T064 Validate scheduler staging before dependencies, dispatch governed convergence, publish the `hpcuser01` identity receipt, and capture scheduler state in less than `60` seconds through `tests/end-to-end/converge_linux_roles.sh`
- [ ] T065 Complete the supported CycleCloud UI user gate with an attestation bound to the current scheduler receipt/specification; when required, generate a protected feature-004-policy one-time password, require reset, discard it immediately, and record only `force-reset-discarded`; then reboot both persistent VMs, prove no silent mutation, and capture both zero-update second runs through `docs/quickstart-evidence-runbook.md` and `tests/end-to-end/converge_linux_roles.sh`
- [ ] T066 Submit the bounded one-node burst job as `hpcuser01`, verify UID `11200`, key access, shared-home ownership, recorded conflict-free primary GID, clean node termination, and UI status without identity conflicts; then produce both the final Terraform no-change plan and final exact CycleCloud deployment-stack what-if from approved inputs through `tests/end-to-end/cyclecloud_stack.sh` and `docs/quickstart-evidence-runbook.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: Starts from the approved feature 004 and feature 005 planning commits.
- **Phase 2 (Foundational)**: Depends on Phase 1 and blocks every user story.
- **Phase 3 (US1)**: Depends on the common lock/artifact/bootstrap/state foundation.
- **Phase 4 (US2)**: Depends on US1 because scheduler dispatch requires a converged CycleCloud
  receipt and imported cluster.
- **Phase 5 (US3)**: Depends on US1 and US2 because it verifies both completed role workflows.
- **Phase 6 (Acceptance)**: Depends on all source implementation and explicit deployment approvals.

### User Story Dependency Graph

```text
Setup -> Foundation -> US1 CycleCloud -> US2 Scheduler/UI Gate -> US3 Audit -> Acceptance
```

### Within Each User Story

- Write each listed test first and confirm that it fails for the intended missing behavior.
- Validate locks, artifacts, and specifications before installation or Chef execution.
- Complete role-local behavior before governed cross-role orchestration.
- Preserve failed-attempt evidence and remove temporary protected values on every exit path.
- Require each story's independent test before advancing.

### Governed Acceptance Order

```text
T059 generate credentials
  -> T060 review/approve plans
  -> T061 apply and rebuild the Windows jump host, CycleCloud appliance, and scheduler
  -> T062 test windowsadmin/hpcadmin logins
  -> T063-T064 validate role convergence
  -> T065 complete UI gate, reboot proof, and idempotency
  -> T066 burst, final Terraform no-change plan, and final CycleCloud what-if
```

### Parallel Opportunities

- T003, T004, and T005 can proceed in parallel after the contract shape is fixed.
- T014 and T015 can proceed in parallel after common manifest fields are fixed.
- T017, T018, and T019 can proceed in parallel after the US1 interfaces are fixed.
- T030, T031, T032, T033, and T034 can proceed in parallel after scheduler inputs are fixed.
- T045 can proceed in parallel with governed workflow implementation after scheduler outcomes are fixed.
- T048, T049, and T050 can proceed in parallel after both wrappers have stable interfaces.

---

## Parallel Example: User Story 1

```text
Task T017: Add CycleCloud bootstrap-order, reboot, and cleanup tests
Task T018: Add CycleCloud wrapper lock/state/retry tests
Task T019: Add CycleCloud InSpec outcome controls
```

## Parallel Example: User Story 2

```text
Task T030: Add scheduler ChefSpec identity/package tests
Task T031: Add managed-identity Key Vault REST tests
Task T032: Add governed dispatch, identity receipt, and UI-gate tests
Task T033: Add sub-minute remote state tests
Task T034: Add scheduler reboot tests
```

## Parallel Example: User Story 3

```text
Task T048: Add governed retry and replacement tests
Task T049: Extend lock-bound idempotency verification
Task T050: Extend secret-hygiene policy coverage
```

---

## Implementation Strategy

### MVP First: User Story 1

1. Complete Setup and Foundational phases.
2. Complete T016-T028.
3. Stop and validate the CycleCloud role using fixtures before any live rebuild.
4. With approval, demonstrate one untouched CycleCloud clean boot independently.

### Incremental Delivery

1. **Foundation**: Deterministic lock-bound artifacts, exact package pins, node specifications, and
   bounded state/evidence.
2. **US1**: Automatic CycleCloud first-run, Chef convergence, and cluster import.
3. **US2**: Dependency-gated scheduler convergence, public-identity receipt, and supported manual
   CycleCloud UI gate.
4. **US3**: Retry, audit, cleanup, reboot safety, state timing, and zero-update verification.
5. **Acceptance**: Deploy new feature 004 credentials before login checks, complete clean rebuilds,
   attest the UI gate, run one bounded burst node, and prove final no change.

### Completion Gate

- All 66 tasks are checked.
- Feature 004's deferred live login acceptance occurs only after the new credentials are deployed.
- Both role manifests and specifications match approved Policyfile lock and artifact digests.
- Both persistent VMs pass reboot safety and sub-minute state inspection.
- The supported manual CycleCloud UI gate is accepted without protected data in evidence.
- Both second convergences report zero resources updated.
- The bounded burst job succeeds as `hpcuser01` with UID `11200` and a recorded conflict-free
  primary GID.
- Secret scans, the final Terraform no-change plan, and the final exact CycleCloud
  deployment-stack what-if pass.
