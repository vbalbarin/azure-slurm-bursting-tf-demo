---

description: "Implementation tasks for user-friendly generated passwords"
---

# Tasks: User-Friendly Generated Passwords

**Input**: Design documents from `/specs/004-user-friendly-passwords/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Required by the specification and implementation plan. Test tasks precede their
corresponding implementation tasks and must fail for the expected reason before implementation.

**Organization**: Tasks are grouped by user story so each increment has a distinct acceptance gate.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it changes a different file and has no incomplete dependency
- **[Story]**: Maps the task to a user story from `spec.md`
- Every task names the exact file it changes or validates

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the standard-library generator and test surfaces without changing live
credential behavior.

- [X] T001 Create the executable Python CLI skeleton with required `--windows-password-file`, `--cyclecloud-password-file`, `--evidence-file`, and `--lock-file` arguments and no literal-password argument in `tests/end-to-end/generate_admin_passwords.py`
- [X] T002 [P] Create shared subprocess, protected-directory, captured-output, and deterministic-random-source fixtures in `tests/end-to-end/test_generate_admin_passwords.py`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Implement shared policy, path, lock, and atomic-write primitives required by every
story.

**⚠️ CRITICAL**: No user story work begins until these primitives pass their focused tests.

- [X] T003 Add failing tests for policy/target models and CLI exit-code mapping (`0` success, `2` invocation/path, `3` partial set, `4` policy/uniqueness, `5` lock, `6` persistence) in `tests/end-to-end/test_generate_admin_passwords.py`
- [X] T004 Implement immutable policy and target metadata in `tests/end-to-end/generate_admin_passwords.py`: ID `interactive-admin-v1`, length exactly `16`, uppercase `ABCDEFGHJKLMNPQRSTUVWXYZ`, lowercase `abcdefghijkmnopqrstuvwxyz`, numeric `23456789`, special `!@#$%^*()-_+=`, minimum exactly `2` per class, and target tuples `windows/windowsadmin/windows-admin-password` and `cyclecloud/hpcadmin/cyclecloud-admin-password`
- [X] T005 Add failing tests for exclusive nonblocking locking, regular-file/no-symlink validation, mode `0600`, same-directory temporary files, flush/`fsync`, atomic replacement, and value-free atomic JSON writes in `tests/end-to-end/test_generate_admin_passwords.py`
- [X] T006 Implement the tested lock, protected-path validation, atomic secret-write, directory durability, and atomic evidence-write helpers in `tests/end-to-end/generate_admin_passwords.py`

**Checkpoint**: Shared primitives reject unsafe paths and can persist protected content without
exposing it.

---

## Phase 3: User Story 1 - Use Generated Application Credentials (Priority: P1) 🎯 MVP

**Goal**: A new run receives a typable, policy-compliant CycleCloud `hpcadmin` password, while a
complete existing set is preserved.

**Independent Test**: In an empty mode-`0700` fixture directory, generate the credential set and
prove the CycleCloud value is exactly 16 approved characters with at least two characters from
each class; rerun and prove both existing files remain byte-for-byte and metadata unchanged.

### Tests for User Story 1

- [X] T007 [US1] Add failing unit tests for guaranteed policy construction and validation in `tests/end-to-end/test_generate_admin_passwords.py`, asserting length exactly `16`, allowed characters only, and at least two uppercase, lowercase, numeric, and `!@#$%^*()-_+=` special characters
- [X] T008 [US1] Add failing subprocess tests for new-set generation, complete-set preservation, mode `0600`, `generated`/`preserved` status, unchanged file bytes and modification times, and zero password data on stdout/stderr in `tests/end-to-end/test_generate_admin_passwords.py`

### Implementation for User Story 1

- [X] T009 [US1] Implement cryptographic password construction with `secrets.choice`, two mandatory characters per class, eight combined-alphabet characters, and `secrets.SystemRandom().shuffle` plus the strict new-value validator in `tests/end-to-end/generate_admin_passwords.py`
- [X] T010 [US1] Implement the locked absent-set and complete-existing-set state transitions in `tests/end-to-end/generate_admin_passwords.py`, preserving existing complete credentials byte-for-byte and setting `newValuePolicyValidated` to `true` only for generated sets and `null` for preserved sets
- [X] T011 [US1] Remove CycleCloud administrator password generation, require the pre-generated mode-`0600` file, and keep TLS/PFX password generation unchanged in `tests/end-to-end/generate_cyclecloud_bootstrap_secrets.sh`
- [X] T012 [US1] Replace the Base64 CycleCloud password instructions with the protected generator invocation and no-change rerun check in `docs/quickstart-evidence-runbook.md`

**Checkpoint**: The CycleCloud application password journey is independently usable and repeatable
without silent rotation.

---

## Phase 4: User Story 2 - Distinguish Administrative Credentials (Priority: P2)

**Goal**: Windows `windowsadmin` and CycleCloud `hpcadmin` receive distinct, correctly labeled
credentials, and storage cannot proceed without value-free accepted evidence.

**Independent Test**: Generate a new set, prove the two protected values differ, validate the two
exact target/account/secret-name tuples in evidence, store them under their existing Key Vault
names, and prove neither value appears in evidence or captured output.

### Tests for User Story 2

- [X] T013 [US2] Add failing tests for cross-credential inequality, forced first-collision regeneration, and the exact Windows/CycleCloud target/account/secret-name mappings in `tests/end-to-end/test_generate_admin_passwords.py`
- [X] T014 [P] [US2] Add failing script tests that reject missing, malformed, nonaccepted, or mislabeled password evidence before any `az keyvault secret set` call in `tests/end-to-end/test_cyclecloud_stack.py`
- [X] T015 [P] [US2] Extend secret-hygiene tests to reject password values, hashes, encoded values, prefixes/suffixes, and character-position data in administrative credential evidence in `tests/policy/test_backend_secret_hygiene.py`

### Implementation for User Story 2

- [X] T016 [US2] Enforce pair inequality with bounded collision regeneration and emit exactly two correctly labeled target records with `uniquenessValidated: true` and `protectedModesValidated: true` in `tests/end-to-end/generate_admin_passwords.py`
- [X] T017 [US2] Require and validate the accepted administrative-password evidence receipt before writing `windows-admin-password` and `cyclecloud-admin-password`, while preserving the seven existing Key Vault secret names and reference-only output, in `tests/end-to-end/store_admin_secrets.sh`
- [X] T018 [US2] Replace the standalone Windows Base64 generator with the single credential-set invocation, document the `windowsadmin` versus `hpcadmin` labels, and keep protected display outside ordinary capture in `docs/quickstart-evidence-runbook.md`

**Checkpoint**: Both administrative credentials are distinct, unambiguous, protected, and accepted
by the existing storage lifecycle.

---

## Phase 5: User Story 3 - Detect Unsafe Credential Generation (Priority: P3)

**Goal**: Invalid values and unsafe filesystem or interrupted states fail before provisioning
without overwriting accepted credentials or leaking protected data.

**Independent Test**: Exercise invalid length/classes/characters, duplicate values, one-file
partial state, symlinks, unsafe modes, active lock, and injected interruption; require the
contracted exit code, no dependent storage call, no secret output, and preservation of all
preexisting files.

### Tests for User Story 3

- [X] T019 [US3] Add failing validation tests for unapproved characters, incorrect length, fewer than two members of every required class, and equal credential values in `tests/end-to-end/test_generate_admin_passwords.py`
- [X] T020 [US3] Add failing state tests for exactly one existing credential, symlink/nonregular targets, non-`0600` existing files, group/world-writable parent directories, lock contention, and interruption immediately before the second replacement in `tests/end-to-end/test_generate_admin_passwords.py`
- [X] T021 [P] [US3] Add integration tests proving missing/failed credential evidence blocks `store_admin_secrets.sh` before Azure CLI mutation and preserves existing storage evidence in `tests/end-to-end/test_cyclecloud_stack.py`

### Implementation for User Story 3

- [X] T022 [US3] Implement fail-closed policy/uniqueness errors and test-only injectable character-source/interruption seams that are unavailable through the production CLI in `tests/end-to-end/generate_admin_passwords.py`
- [X] T023 [US3] Implement `partial_credential_set`, unsafe-path/mode, lock-unavailable, and persistence failure handling with contract exit codes and no create/delete/chmod/overwrite of existing credential files in `tests/end-to-end/generate_admin_passwords.py`
- [X] T024 [US3] Add bounded non-secret failure codes to the password generation and storage steps, ensuring every nonzero result stops dependent TLS/bootstrap or Key Vault actions, in `tests/end-to-end/generate_cyclecloud_bootstrap_secrets.sh` and `tests/end-to-end/store_admin_secrets.sh`

**Checkpoint**: All required negative and interruption paths fail closed without credential
rotation or disclosure.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Wire validation, documentation, and cross-feature acceptance after all stories pass.

- [X] T025 Register `tests/end-to-end/test_generate_admin_passwords.py` in the `end-to-end-unit` target and add Python syntax checking for `tests/end-to-end/generate_admin_passwords.py` in `Makefile`
- [X] T026 [P] Update feature 004 validation, preservation, partial-state recovery, Key Vault, and login procedures and feature 005 prerequisite references in `docs/quickstart-evidence-runbook.md`
- [X] T027 Run the feature 004 quickstart and targeted tests, then record only command/result metadata and no protected values in `specs/004-user-friendly-passwords/quickstart.md`
- [ ] T028 Run full `make validate`, perform protected `windowsadmin` and `hpcadmin` login acceptance for a new run, and record secret-free pass/fail evidence through the procedures in `docs/quickstart-evidence-runbook.md`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies.
- **Phase 2 (Foundational)**: Depends on Phase 1 and blocks every user story.
- **Phase 3 (US1)**: Depends on Phase 2; this is the MVP.
- **Phase 4 (US2)**: Depends on US1 because it extends the generated set with enforced
  cross-credential identity and the storage gate.
- **Phase 5 (US3)**: Depends on US1 and US2 because it hardens their complete workflow and failure
  boundaries.
- **Phase 6 (Polish)**: Depends on all selected user stories.
- **Feature 005**: Its implementation begins only after feature 004 completes its accepted
  credential receipt and Key Vault reference gates.

### User Story Dependency Graph

```text
Setup -> Foundation -> US1 (P1/MVP) -> US2 (P2) -> US3 (P3) -> Polish -> Feature 005
```

### Within Each User Story

- Write each listed test first and confirm it fails for the expected missing behavior.
- Implement policy/models before state transitions.
- Implement state transitions before shell/runbook integration.
- Preserve existing values and evidence on every failure.
- Complete the independent test before starting the next story.

### Parallel Opportunities

- T001 and T002 can proceed in parallel.
- T014 and T015 can proceed in parallel after US1.
- T021 can be prepared in parallel with T019/T020 because it changes a separate integration test
  file, but implementation waits for the generator failure contract.
- T026 can proceed in parallel with T025 after all story behavior is stable.

---

## Parallel Example: User Story 1

```text
No implementation tasks within US1 are parallel: T007-T012 deliberately follow a tests-first,
generator-before-integration sequence.
```

## Parallel Example: User Story 2

```text
Task T014: Add rejected-evidence storage script tests in tests/end-to-end/test_cyclecloud_stack.py
Task T015: Add value/derivative evidence hygiene tests in tests/policy/test_backend_secret_hygiene.py
```

## Parallel Example: User Story 3

```text
Task T019/T020: Add generator policy and filesystem/state tests in tests/end-to-end/test_generate_admin_passwords.py
Task T021: Add storage-blocking integration tests in tests/end-to-end/test_cyclecloud_stack.py
```

---

## Implementation Strategy

### MVP First: User Story 1

1. Complete Setup and Foundational phases.
2. Complete T007-T012.
3. Stop and independently validate a compliant CycleCloud password and no-change rerun.
4. Do not use the new generator for an accepted environment until US2 uniqueness/storage gating
   and US3 failure controls are complete.

### Incremental Delivery

1. **US1**: Deliver compliant CycleCloud application credentials and preservation.
2. **US2**: Deliver the distinct labeled Windows/CycleCloud set and accepted storage evidence.
3. **US3**: Deliver fail-closed invalid, partial, concurrent, and interrupted-state handling.
4. **Polish**: Wire full validation and protected target login acceptance.
5. **Feature 005**: Consume the accepted receipt and existing Key Vault secret references.

### Completion Gate

- All 28 tasks are checked.
- Every story's independent test passes.
- Repeated generation preserves complete existing credentials with zero changes.
- Negative tests prove no password or reversible derivative reaches logs/evidence.
- Full validation and both protected target logins succeed before feature 005 clean-boot testing.
