# Implementation Plan: User-Friendly Generated Passwords

**Branch**: `004-user-friendly-passwords` | **Date**: 2026-10-23 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/004-user-friendly-passwords/spec.md`

## Summary

Replace the two independent long Base64 password generators with one protected, testable
credential-set generator for new evidence runs. Generate distinct 16-character Windows and
CycleCloud administrator passwords from unambiguous letters, digits, and
`!@#$%^*()-_+=`, require at least two characters from each class, validate before any accepted
write, preserve existing credentials without silent rotation, and emit value-free policy evidence.
Feature 005 consumes the completed protected credential set and validation receipt as a
prerequisite.

## Technical Context

**Language/Version**: Python 3.12 and Bash 5  
**Primary Dependencies**: Python standard-library `secrets`, `fcntl`, `json`, and `pathlib`;
existing OpenSSL and Azure CLI workflow tools  
**Storage**: Root/operator-protected run-state files at mode `0600`; existing private Azure Key
Vault secret names remain unchanged  
**Testing**: Pytest unit and subprocess contract tests, Bash syntax checks, existing policy and
end-to-end unit suites  
**Target Platform**: Governed Linux deployment runner; credentials consumed by Azure Windows VM
deployment and CycleCloud 8.9.3 first-run  
**Project Type**: Protected deployment-workflow utility  
**Performance Goals**: Generate and validate one credential set in under one second; no retries
visible to the operator under normal entropy availability  
**Constraints**: Exactly 16 characters for newly generated interactive passwords; at least two
uppercase, lowercase, numeric, and safe-special characters; no value, hash, or reversible
derivative in output/evidence; no automatic rotation  
**Scale/Scope**: Two interactive administrative passwords per evidence run

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Pre-design evaluation | Post-design evaluation |
|---|---|---|
| I. Compliance-Preserving Legacy Operation | PASS: existing protected credentials remain authoritative and are not rotated. | PASS: complete existing sets are preserved byte-for-byte; partial or invalid state fails without destructive repair. |
| II. Declarative Infrastructure and Managed Node Configuration | PASS: this is pre-deployment protected input generation, not Azure control-plane or node configuration. | PASS: no infrastructure or guest resource is created by the generator. |
| III. Azure Verified Modules and Appliance Exception | PASS: no Azure resource definition changes are required. | PASS: Key Vault names and existing AVM resources are unchanged. |
| IV. Security Without Exception | PASS: cryptographic randomness, protected files, fail-closed validation, and value-free evidence are required. | PASS: contracts prohibit stdout values and derived fingerprints; Key Vault writes remain in the existing bounded lifecycle. |
| V. Reliable, Idempotent, and Validated Change | PASS: deterministic policy validation, preservation, interruption, duplicate, and invalid-input cases are testable. | PASS: complete sets produce no writes; staged writes are atomic per file; partial state is never silently replaced. |

No constitutional exception is required.

## Project Structure

### Documentation (this feature)

```text
specs/004-user-friendly-passwords/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── credential-evidence.schema.json
│   ├── credential-policy.schema.json
│   └── generator-cli.md
└── tasks.md
```

### Source Code (repository root)

```text
tests/end-to-end/
├── generate_admin_passwords.py
├── generate_cyclecloud_bootstrap_secrets.sh
├── store_admin_secrets.sh
├── test_generate_admin_passwords.py
└── test_cyclecloud_stack.py

docs/
└── quickstart-evidence-runbook.md

Makefile
```

**Structure Decision**: Keep credential generation in the existing governed end-to-end workflow.
Use a focused Python utility because exact class counts, cryptographic selection, unbiased secure
shuffling, locking, protected atomic writes, and non-secret JSON evidence are substantially safer
and more testable than shell pipelines. Bash remains responsible for orchestration and TLS
generation.

## Phase 0: Research Outcomes

[research.md](./research.md) resolves policy profiles, character selection, secure generation,
existing/partial-state behavior, atomicity, evidence, and integration with feature 005.

## Phase 1: Design Outcomes

- [data-model.md](./data-model.md) defines policy profiles, credential records, credential-set
  states, validation, and state transitions.
- [contracts/](./contracts/) defines policy/evidence JSON and the secret-safe CLI behavior.
- [quickstart.md](./quickstart.md) defines runnable generation, preservation, invalid-input,
  interruption, storage, and login validation.

## Cross-Feature Dependency

Feature `005-automated-chef-bootstrap` depends on this feature's accepted credential-set receipt:

1. Feature 004 generates or preserves the protected Windows and CycleCloud password files.
2. Feature 004 validates new values and records value-free evidence.
3. The existing bounded Key Vault write lifecycle stores the unchanged secret names.
4. Feature 005 may begin clean-boot convergence only after that receipt and the Key Vault secret
   references pass its dependency gate.

Feature 005 must not duplicate password generation or rotate a credential produced by feature 004.

## Implementation Sequence

1. Add failing tests for policy validation, generation, uniqueness, preservation, partial state,
   protected modes, stdout hygiene, locking, and interruption.
2. Implement the standard-library generator and its JSON contracts.
3. Replace Windows and CycleCloud administrator password generation in the runbook/bootstrap
   workflow while leaving TLS/PFX password generation machine-oriented and out of scope.
4. Add value-free validation evidence to the existing protected secret-write prerequisites.
5. Update validation targets and operator documentation.
6. Run targeted tests, full validation, a new-run generation check, repeat/no-change check, and
   CycleCloud/Windows interactive login acceptance.
