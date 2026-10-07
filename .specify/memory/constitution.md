# Azure Slurm Bursting Terraform Demo Constitution

## Core Principles

### I. Compliance-Preserving Legacy Operation
The existing Azure workload MUST remain operational and retained for its compliance purpose.
Infrastructure changes MUST preserve required resources, configuration, data, auditability, and
traceability unless an authorized compliance decision explicitly permits a change. Every proposed
change MUST identify its compliance impact and MUST avoid destructive replacement or deletion of
retained resources without documented approval. This ensures modernization work does not defeat
the reason the legacy workload continues to exist.

### II. Terraform Infrastructure and Managed Node Configuration
All Azure control-plane infrastructure definitions and changes MUST use Terraform configuration.
Declarative Terraform is the sole infrastructure control plane so resource changes remain
reviewable, repeatable, and represented in state. Configuration inside provisioned, general-purpose
infrastructure nodes is a separate concern and MUST use an established configuration-management
platform such as Chef, Puppet, Ansible, or Desired State Configuration when that platform can
perform the task. Node configuration content MUST be version-controlled, repeatable, non-interactive,
and idempotent. Configuration-management tools and their content MUST NOT create, mutate, or delete
Azure control-plane resources outside Terraform.

Python or Bash MAY be used only to process configuration files consumed by infrastructure nodes
when the selected configuration-management platform cannot safely perform the required
transformation. Each exception MUST document why the platform is insufficient, its inputs and
outputs, and its failure behavior. Exception code MUST inspect current state, avoid a write when
content is already correct, validate generated content before replacement, use an atomic update,
and return a nonzero status without replacing the last valid file on failure. Repeated execution
with unchanged inputs MUST produce no configuration change. Exception scripts MUST NOT provision
infrastructure, invoke deployments, or act as a substitute for configuration management.

### III. Azure Verified Modules Only
Azure infrastructure MUST be composed exclusively from published Azure Verified Modules (AVM)
for Terraform. Direct Azure resource blocks, custom modules, and forks or copied implementations
of AVM modules MUST NOT be used. Module sources and versions MUST be explicitly pinned. Terraform
language constructs and provider, data, local, variable, and output declarations MAY be used to
connect and configure AVM modules, but MUST NOT circumvent this module requirement. If no suitable
AVM exists, implementation MUST stop until the requirement or this constitution is amended.

### IV. Security Without Exception
Every design, change, and deployment MUST apply Azure and Terraform security best practices.
Configurations MUST enforce least privilege, secure defaults, encryption where supported,
protected secret handling, restricted network access, and auditable access. Secrets MUST NOT be
committed to source control, embedded in Terraform configuration, or exposed through outputs.
Security controls MUST NOT be weakened to preserve compatibility, reduce effort, or accelerate a
deployment; exceptions require a constitution amendment before implementation.

### V. Reliable, Idempotent, and Validated Change
Infrastructure and node configuration MUST be deterministic, idempotent, version-pinned, and safe
for the retained workload. Resource replacement and deletion risks MUST be reviewed in every
Terraform plan, and retained resources MUST use appropriate lifecycle protections when AVM
interfaces permit them. Before any deployment or apply, the exact infrastructure configuration to
be deployed MUST pass formatting and Terraform validation, and its plan MUST be reviewed for
unintended changes. Configuration-management content and permitted exception scripts MUST pass
their native validation and an idempotency test before use. A failed or stale validation, plan, or
idempotency test MUST block deployment. These controls provide reliability without introducing
unrequired high-availability, disaster-recovery, or scaling architecture.

## Workload Scope and Constraints

- The project supports a legacy Azure workload retained for compliance reasons.
- High availability is not a requirement and MUST NOT be added without an approved requirement
  and constitution amendment.
- Disaster recovery is not a requirement and MUST NOT be added without an approved requirement
  and constitution amendment.
- Scalability beyond the workload's established operating needs is not a requirement and MUST NOT
  drive additional infrastructure without an approved requirement and constitution amendment.
- Designs MUST favor the simplest AVM-based topology that preserves the workload and satisfies
  security, reliability, and compliance obligations.
- Cost, complexity, and operational burden introduced solely for high availability, disaster
  recovery, or scalability MUST be rejected while these capabilities remain out of scope.

## Infrastructure Delivery Workflow

1. Define every Azure control-plane infrastructure change in Terraform using pinned AVM module
   versions.
2. Define node configuration in a supported configuration-management platform. When an allowed
   Python or Bash exception is necessary, record why the platform cannot perform the task and
   verify that the exception is limited to processing a node-consumed configuration file.
3. Review the change for compliance retention, security controls, reliability, idempotency,
   prohibited control-plane scripting, and non-AVM Azure resources.
4. Run `terraform fmt -check` and initialize Terraform sufficiently to run
   `terraform validate`; both commands MUST succeed before a deployment plan is approved.
5. Run native validation for configuration-management content and permitted exception scripts.
   Test initial application, repeated application with unchanged inputs, already-compliant state,
   and invalid input. The repeated and already-compliant cases MUST report no change, and invalid
   input MUST preserve the last valid configuration.
6. Generate a Terraform plan from the same configuration and inputs intended for deployment.
   Review resource creation, mutation, replacement, and deletion, with explicit attention to
   retained legacy resources and security controls.
7. Run `terraform apply` only from the successfully validated and reviewed plan, then apply only
   the validated node configuration. Any infrastructure, node-configuration, module, provider,
   variable, input, or state-context change after validation MUST invalidate the applicable gate
   and require validation and review again.
8. Record infrastructure validation, plan review, node-configuration validation, exception
   justification, and idempotency-test evidence with the change for compliance traceability.

## Governance

This constitution supersedes conflicting project practices, documentation, and convenience.
Amendments MUST be proposed in writing, explain their compliance and operational impact, receive
approval from the project's accountable maintainers, and include a migration plan when existing
infrastructure or workflows are affected.

Constitution versions follow semantic versioning: MAJOR for incompatible principle removals or
redefinitions, MINOR for new principles or materially expanded obligations, and PATCH for
non-semantic clarifications. Every infrastructure specification, plan, review, and deployment MUST
demonstrate compliance with the current constitution. Reviewers MUST block changes that violate a
MUST rule. Compliance MUST be re-evaluated whenever Terraform, provider, AVM,
configuration-management tool, or permitted script-runtime versions change and before every
deployment.

**Version**: 2.0.0 | **Ratified**: 2026-10-07 | **Last Amended**: 2026-10-07
