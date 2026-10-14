# Implementation Plan: Terraform State Backend Bootstrap

**Branch**: `003-terraform-backend-bootstrap` | **Date**: 2026-10-13 |
**Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/003-terraform-backend-bootstrap/spec.md`

## Summary

Add a separate Terraform bootstrap root that creates one governed Azure Blob state backend before
the demo or capacity-probe roots initialize. The root calls pinned Azure Verified Modules directly
for a resource group and storage account, defaults to a firewall-deny storage endpoint allow-listed
to approved public IPv4 CIDRs, and optionally creates a Blob private endpoint against a pre-existing
subnet and private DNS zone. An approved Entra operator group and optional workload identity receive
container-scoped `Storage Blob Data Contributor`; shared-key and anonymous access remain disabled.

Bootstrap starts with sensitive local state in a separate protected `/state` volume, applies only an
exact reviewed plan, validates the backend, then uses an ignored backend override and
`terraform init -migrate-state` to move bootstrap state to
`<environment>/bootstrap.tfstate`. Main and capacity-probe roots consume secret-free readiness JSON
and use `<environment>/main.tfstate` and `<environment>/capacity-probe.tfstate`. Existing
organizational backends are validate-only and never imported or managed. Before managed-backend
removal, dependent state must be empty, bootstrap state migrates back to protected local storage,
the deletion lock is removed through a separately reviewed change, and only then may a reviewed
destroy plan run.

## Technical Context

**Language/Version**: Terraform 1.16.5 in the development container; bootstrap root requires
Terraform >= 1.10 and < 2.0; existing main and capacity-probe roots retain >= 1.9 and < 2.0; HCL and
Terraform test files; no new Bash or Python runtime implementation for readiness, lifecycle,
provisioning, or apply

**Primary Dependencies**: AzAPI provider 2.12.0; pinned
`Azure/avm-res-resources-resourcegroup/azurerm` 0.4.0 and
`Azure/avm-res-storage-storageaccount/azurerm` 0.10.0; Terraform `azurerm` backend; Azure CLI 2.91.0
for interactive Entra authentication and direct read-only data-plane checks; `jq`, `sha256sum`,
`getent`, and `curl` as direct documented operator commands rather than custom scripts

**Storage**: Protected local bootstrap state under a dedicated `/state` named volume before and
during migration; Azure Blob container `tfstate` for the three environment-scoped state objects;
blob/container soft delete and versioning retained for seven days; secret-free validation and
approval evidence under `/evidence`

**Testing**: `terraform fmt -check`, initialization without the remote backend, `terraform
validate`, TFLint, Checkov, native Terraform tests with mocked providers, policy tests enforcing
AVM-only composition, deterministic readiness/lifecycle classification fixtures, direct
operator-executed local-to-remote-to-local migration acceptance with Python limited to validating
the resulting secret-free evidence, digest-mismatch and stale-plan tests, lock-conflict evidence,
execution-context mismatch and stale-assertion tests, idempotent second plan, existing-backend
validate-only test, timed live Azure acceptance, automated secret-hygiene inspection, and JSON
Schema contract tests

**Target Platform**: Linux development container or governed Linux runner authenticated to an
approved Azure tenant/subscription; default restricted-public Blob endpoint with explicit public
IPv4 allow-list; optional Blob private endpoint using a pre-existing reachable subnet and private
DNS zone

**Project Type**: Infrastructure-as-code bootstrap root plus read-only validation and evidence
contracts integrated with the existing infrastructure repository

**Performance Goals**: Complete managed bootstrap and validated coordinates in at most 20 minutes
excluding role-propagation delay; recover a second authorized operator in at most 15 minutes;
readiness failures return before either dependent plan starts

**Constraints**: All Azure resources through direct pinned AVM calls; no direct Azure resource
blocks or local wrapper modules; no shared keys, SAS, anonymous container access, unrestricted
public network access, credential output, or state in the evidence volume; exact reviewed plans
only, with an external approval record created after plan generation and verified immediately
before manual apply; three distinct state keys; deterministic ALZ-style names with
operator-provided uniqueness; no HA, geo-DR, scaling, automatic backend adoption, or custom
Bash/Python readiness, lifecycle, provisioning, or apply implementation

**Scale/Scope**: One managed or validate-only backend per environment; one resource group, one
storage account, one private container, one operator group assignment, zero or one workload
identity assignment, zero or one Blob private endpoint, and exactly three state objects during
ordinary operation

## Constitution Check

*GATE: Passed before Phase 0 research. Re-checked after Phase 1 design.*

| Principle | Design evidence | Status |
|---|---|---|
| Compliance-preserving legacy operation | Feature adds an isolated prerequisite and does not mutate retained workload resources. Existing organizational backends are validate-only. Every apply, migration, unlock, and removal is separately reviewed and evidenced. | PASS |
| Terraform infrastructure and managed node configuration | Terraform is the only Azure control plane. Direct operator commands perform read-only probes and backend migration. Native Terraform locals, checks, preconditions, and outputs classify readiness and lifecycle evidence; no custom Bash/Python implementation creates, validates, or deploys infrastructure. | PASS |
| Azure Verified Modules only | Managed mode calls pinned resource-group and storage-account AVMs directly. The storage AVM owns container, network rules, role assignments, private endpoint, and lock. Existing mode creates no resources. | PASS |
| Security without exception | Entra-only data access, group-based least privilege, disabled shared keys and anonymous access, default-deny firewall, selectable private endpoint, encryption, soft delete, versioning, protected state, and secret-free evidence are explicit. | PASS |
| Reliable, idempotent, validated change | Exact reviewed plans, digest-bound approvals, backend readiness, round-trip migration tests, native locking, deletion locks, second no-change plans, and teardown gates fail closed. | PASS |
| Scope constraints | One small state backend without HA, geo-redundancy, automatic failover, or unnecessary scale is the simplest secure topology. | PASS |

### Pre-design gate

Research confirmed current published AVMs cover all managed Azure resources. Storage AVM 0.10.0
requires Terraform >= 1.10, which is satisfied by the pinned development container without raising
the existing roots' declared minimum. The storage module exposes containers, network rules, Blob
private endpoints, role assignments, encryption controls, and management locks. The resource-group
module remains pinned at 0.4.0. No direct resource is needed.

The bootstrap chicken-and-egg is resolved by keeping initial state in `/state`, adding an ignored
backend override only after preliminary readiness succeeds, and using
`terraform init -migrate-state` rather than `-reconfigure`. The reverse migration is a mandatory
tested teardown gate. Operators execute documented read-only Azure CLI, DNS, HTTP, and Terraform
commands directly and record their non-secret results in protected, schema-conforming readiness
assertions. Assertions include stable command IDs, observation times, exit codes, non-secret
observed values, exact coordinates digest, and a digest of the observed runner/network context.
Native Terraform logic validates assertion freshness and context binding, classifies failures, and
emits the contract document. No custom Bash/Python implementation or constitution exception is
required.

### Post-design gate

The data model, JSON contracts, lifecycle contract, and quickstart preserve the pre-design
boundaries. Managed Azure changes remain exclusively in direct AVM calls. Existing-backend mode
creates and imports nothing. Sensitive state is isolated from evidence. Private networking depends
on an existing approved network path rather than adding demo networking. Readiness and lifecycle
classification remain native Terraform behavior, while direct operator commands perform only
read-only inspection, state migration, and native lock verification. No Phase 1 artifact adds
direct resources, custom modules, secret authentication, public fallback, custom control-plane
scripting, unreviewed apply, HA, DR, or additional scale. All gates remain PASS.

## Project Structure

### Documentation (this feature)

```text
specs/003-terraform-backend-bootstrap/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── checklists/
│   └── requirements.md
├── contracts/
│   ├── backend-inputs.md
│   ├── backend-lifecycle.md
│   ├── backend-coordinates.schema.json
│   ├── backend-readiness.schema.json
│   ├── backend-readiness-assertions.schema.json
│   ├── backend-lifecycle.schema.json
│   ├── backend-migration-acceptance.schema.json
│   ├── backend-live-acceptance.schema.json
│   └── backend-plan-approval.schema.json
└── tasks.md
```

### Source Code (repository root)

```text
.devcontainer/
├── devcontainer.json
├── Dockerfile
└── post-create.sh

terraform/
├── bootstrap/
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── locals.tf
│   ├── resource-group.tf
│   ├── storage.tf
│   ├── existing-backend.tf
│   ├── readiness.tf
│   ├── lifecycle.tf
│   ├── outputs.tf
│   ├── backend.local.tf.example
│   ├── backend.azurerm.tf.example
│   ├── bootstrap.tfvars.example
│   └── tests/
│       ├── naming.tftest.hcl
│       ├── managed-backend.tftest.hcl
│       ├── private-backend.tftest.hcl
│       ├── existing-backend.tftest.hcl
│       ├── readiness.tftest.hcl
│       └── lifecycle.tftest.hcl
├── versions.tf
├── variables.tf
├── backend-readiness.tf
├── backend.hcl.example
├── backend-readiness.json.example
├── tests/
│   └── backend-readiness.tftest.hcl
└── capacity-probe/
    ├── versions.tf
    ├── variables.tf
    ├── backend-readiness.tf
    ├── backend.hcl.example
    ├── backend-readiness.json.example
    └── tests/
        └── backend-readiness.tftest.hcl

tests/
├── policy/
│   └── test_backend_secret_hygiene.py
└── end-to-end/
    ├── fixtures/
    │   └── backend-migration/
    │       └── main.tf
    ├── test_backend_live_acceptance_evidence.py
    ├── test_backend_migration_evidence.py
    └── test_backend_state_contracts.py

Makefile
README.md
docs/
└── quickstart-evidence-runbook.md
```

**Structure Decision**: Add one independent root under `terraform/bootstrap`; do not introduce a
custom Terraform module. Keep managed mode and validate-only existing mode in the same root behind
an explicit ownership-mode input. Add native Terraform readiness/lifecycle classification that
consumes protected, provenance-bearing results from direct documented read-only operator commands,
binds them to the current non-secret execution-context digest, and emits schema-conforming
secret-free outputs. Add a second named development-container volume for
sensitive bootstrap state, separate from secret-free evidence. Extend both dependent roots with
native readiness-evidence checks so plans fail before resource evaluation when backend coordinates
or evidence are stale or mismatched. Plan approval is external to Terraform inputs: generate the
saved plan, create its SHA-256 approval record, verify that record immediately before applying the
exact plan, and rely on Terraform to reject stale state. Python acceptance tests validate only
schema-bound evidence produced by direct operator commands; they MUST NOT invoke Terraform, Azure
CLI, migration, provisioning, apply, unlock, or destroy operations.

## Complexity Tracking

No constitution violations require justification.
