# Feature Specification: User-Friendly Generated Passwords

**Feature Branch**: `[004-user-friendly-passwords]`

**Created**: 2026-10-23

**Status**: Draft

**Input**: User description: "Add a feature for later implementation that generates more end-user-friendly passwords, similar to the constrained password generation in vbalbarin/tf-cyclecloud-demo."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Use Generated Application Credentials (Priority: P1)

As a demo operator, I can retrieve and type a generated CycleCloud application password without
encountering unsupported characters or an unnecessarily long opaque value.

**Why this priority**: Application login is required to validate and operate the demo. A password
that is difficult to type or violates CycleCloud policy blocks the primary user journey.

**Independent Test**: Generate a new CycleCloud application password, verify its policy properties,
and use it to sign in as the configured application administrator.

**Acceptance Scenarios**:

1. **Given** a new evidence run without an existing CycleCloud password, **When** protected
   credentials are generated, **Then** the application password is exactly 16 characters long and
   uses only letters, numbers, and the approved safe special characters.
2. **Given** the generated application password, **When** the configured administrator signs in to
   CycleCloud, **Then** authentication succeeds without changing or normalizing the password.
3. **Given** an existing protected CycleCloud password, **When** credential generation is repeated,
   **Then** the existing value is preserved rather than silently rotated.

---

### User Story 2 - Distinguish Administrative Credentials (Priority: P2)

As a demo operator, I receive separate passwords for the Windows administrator and CycleCloud
application administrator so that the intended credential is clear and compromise of one does not
grant access to the other.

**Why this priority**: Distinct credentials reduce confusion and preserve security boundaries
between operating-system and application access.

**Independent Test**: Generate both credentials for a new run and verify that they satisfy their
respective policies, have distinct values, and retain unambiguous labels in protected storage.

**Acceptance Scenarios**:

1. **Given** a new evidence run, **When** Windows and CycleCloud credentials are generated,
   **Then** their values are different.
2. **Given** both generated credentials, **When** an operator views the protected credential
   locations, **Then** each value has an unambiguous account and target-system label.
3. **Given** either credential is displayed for interactive use, **When** evidence is collected,
   **Then** the credential value is absent from evidence and logs.

---

### User Story 3 - Detect Unsafe Credential Generation (Priority: P3)

As a maintainer, I receive a clear failure before deployment when a generated password does not
meet its target system's length, character, complexity, or uniqueness requirements.

**Why this priority**: Fail-closed validation prevents rare random-generation defects from appearing
only during first-run bootstrap or interactive login.

**Independent Test**: Validate compliant and deliberately invalid password fixtures and confirm
that only compliant, distinct credentials can proceed to protected storage.

**Acceptance Scenarios**:

1. **Given** a password containing a character outside the approved set, **When** validation runs,
   **Then** generation fails without storing or displaying the invalid value.
2. **Given** a password missing a required character class, **When** validation runs, **Then**
   generation fails with a non-secret explanation.
3. **Given** two generated administrative passwords with the same value, **When** validation runs,
   **Then** generation fails and neither duplicate is accepted for the run.

### Edge Cases

- A random generation attempt does not produce the required number of characters from every class.
- An existing protected password predates this feature and does not satisfy the new usability
  profile.
- A generated value contains quoting, path, shell, JSON, or keyboard-layout-sensitive characters.
- Credential generation is interrupted after one password is written but before all required
  credentials are complete.
- The approved character sets for Windows and CycleCloud differ.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST generate new interactive administrative passwords with exactly
  16 characters.
- **FR-002**: Each generated password MUST contain at least two uppercase letters, two lowercase
  letters, two numbers, and two special characters.
- **FR-003**: CycleCloud application passwords MUST use special characters only from
  `!@#$%^*()-_+=`, which is within CycleCloud's documented built-in password policy.
- **FR-004**: Passwords for other target systems MUST use a target-approved subset that is no less
  usable than the CycleCloud set and MUST satisfy the target's documented policy.
- **FR-005**: Generated Windows and CycleCloud administrative passwords MUST have distinct values.
- **FR-006**: The system MUST validate length, allowed characters, required character counts, and
  cross-credential uniqueness before accepting generated credentials.
- **FR-007**: Invalid generated values MUST be discarded without being written to protected
  storage, logs, console output, source control, or evidence.
- **FR-008**: Repeated execution MUST preserve an existing protected credential unless an operator
  explicitly invokes an approved rotation workflow.
- **FR-009**: The feature MUST NOT automatically rotate credentials in an already deployed
  environment.
- **FR-010**: Protected credential names and operator instructions MUST clearly distinguish the
  target system and account.
- **FR-011**: Secret-free evidence MUST record whether policy and uniqueness validation passed,
  without recording password values or reversible password-derived material.
- **FR-012**: Credential generation failure MUST stop dependent provisioning and first-run
  configuration.

### Key Entities

- **Generated Credential**: A protected password associated with one target system and account,
  including non-secret policy-validation status and creation context.
- **Password Policy Profile**: The target-specific length, allowed-character, complexity, and
  usability requirements applied before a generated credential is accepted.
- **Credential Set**: The administrative credentials generated for one evidence run, whose members
  must remain individually valid and mutually distinct.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of generated CycleCloud passwords are exactly 16 characters and satisfy all
  documented CycleCloud built-in password rules before storage.
- **SC-002**: 100% of new evidence runs produce distinct Windows and CycleCloud administrative
  passwords.
- **SC-003**: An operator can accurately type either generated password from protected display into
  its intended login form on the first attempt in under 60 seconds.
- **SC-004**: All invalid-character, insufficient-complexity, duplicate-value, and interrupted-run
  test cases fail before dependent provisioning begins.
- **SC-005**: Repeating credential generation with an existing complete credential set results in
  zero credential changes.
- **SC-006**: No generated password or reversible password-derived value appears in source control,
  routine logs, or secret-free evidence.

## Assumptions

- This feature applies to credentials intended for interactive operator use; machine-only keys,
  certificate passwords, and service-generated authentication keys remain outside its initial
  scope.
- Sixteen characters with at least two characters from each required class provides the intended
  balance of usability and strength for this demo.
- The safe CycleCloud special-character set follows the established reference implementation:
  `!@#$%^*()-_+=`.
- Existing deployed credentials remain valid and are not rotated merely because this feature is
  introduced.
- Credential values remain in the project's existing protected secret-storage boundary.
