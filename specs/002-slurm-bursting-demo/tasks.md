---

description: "Implementation tasks for the secure Slurm bursting demonstration"
---

# Tasks: Secure Slurm Bursting Demonstration

**Input**: Design documents from `/specs/002-slurm-bursting-demo/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md, constitution.md

**Tests**: Tests are required by the specification, contracts, and constitution. Create each test before the implementation it verifies and confirm it fails for the expected reason.

**Organization**: Tasks are grouped by user story so each story can be implemented and tested as an independently reviewable increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it changes different files and has no dependency on an incomplete task
- **[Story]**: Maps the task to a user story from spec.md
- Every task names the exact file or directory it changes

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Establish the pinned toolchains, source layout, and validation entry points used by every story.

- [X] T001 Create the planned Terraform, Chef, Python, policy, and end-to-end directory structure with placeholder-free entry files under `terraform/`, `chef/`, `tools/headless_template/`, and `tests/`
- [X] T002 Configure Terraform `>= 1.9, < 2.0`, pinned AzureRM and AzAPI providers, and the remote-backend declaration without credentials in `terraform/versions.tf` and `terraform/providers.tf`
- [X] T003 [P] Initialize the Python 3 headless-template package with pinned pytest, type-checking, and Bandit development tooling and no Azure SDK dependency in `tools/headless_template/pyproject.toml`
- [X] T004 [P] Define pinned Chef cookbook metadata and Policyfile entry points for CycleCloud and Slurm in `chef/cookbooks/cyclecloud_node/metadata.rb`, `chef/cookbooks/slurm_scheduler/metadata.rb`, `chef/policyfiles/cyclecloud.rb`, and `chef/policyfiles/slurm.rb`
- [X] T005 [P] Configure Test Kitchen suites and InSpec verifier wiring for both Chef policies in `chef/kitchen.yml`
- [X] T006 [P] Add repository validation commands for Terraform fmt/validate/TFLint/Checkov, Chef Cookstyle/unit/Kitchen, Python type/Bandit/pytest, and policy tests in `Makefile`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Define shared inputs, naming, bootstrap boundaries, validation policy, and evidence formats before any user-story implementation.

**CRITICAL**: No user-story implementation begins until this phase is complete.

- [X] T007 Define validated Terraform inputs for the authorized subscription and tenant, Azure-safe lowercase `environment_name`, distinct supported `source_region` and `burst_region`, private non-overlapping CIDRs, existing Entra operator groups, pinned images and SKUs, stable `cluster_name`, positive `idle_timeout`, and sensitive credential references in `terraform/variables.tf`
- [X] T008 Define deterministic resource names, subnet maps, private DNS names, approved flow tuples, pinned CycleCloud `8.9.3` metadata, common tags, and one-node acceptance limits in `terraform/locals.tf`
- [X] T009 [P] Add a redacted example environment containing no secret values in `terraform/environments/demo.tfvars.example`
- [X] T010 [P] Create minimal VM bootstrap entry points that install and invoke only pinned Chef Local policies and never perform Azure control-plane operations in `chef/bootstrap/linux.sh` and `chef/bootstrap/windows.ps1`
- [X] T011 [P] Define the machine-readable inventory and audit-evidence schema for private names and addresses, selected versions, cluster identity, validation references, and lifecycle states without secret values in `tests/schemas/inventory.schema.json` and `tests/schemas/audit-evidence.schema.json`
- [X] T012 [P] Create static policy tests that reject direct `azurerm_*` and `azapi_*` resource blocks, local/custom Terraform modules, unpinned module sources, public IPs, public Key Vault access, nonsensitive secret outputs, and Chef Azure control-plane operations in `tests/policy/test_constitution.py`
- [X] T013 [P] Create Terraform input-validation tests for identical regions, overlapping CIDRs, unsupported source/burst regions, unavailable images/SKUs/global peering, invalid names, nonpositive idle timeout, and unaccepted Marketplace terms in `tests/terraform/input_validation.tftest.hcl`
- [X] T014 Implement a fail-closed preflight that records both regions, required regional capabilities, global peering support, quota and burst capacity, image and SKU availability, Marketplace terms, CycleCloud `8.9.3`, and selected AlmaLinux/Windows image compatibility without automatic substitution in `tests/end-to-end/preflight.sh`
- [X] T015 Document the exact saved-plan review and approval gate, plan digest recording, invalidation rules, and exact-plan apply procedure in `README.md`

**Checkpoint**: Shared contracts and validation gates are ready; story implementation can begin.

---

## Phase 3: User Story 1 - Provision a Secure Demonstration Environment (Priority: P1) MVP

**Goal**: Provision two privately connected network sites, protected administration, a private secret store, three private hosts, and 90-day operational logging exclusively through pinned Azure Verified Modules.

**Independent Test**: Provision an empty approved scope and verify the complete resource inventory, bidirectional approved connectivity and DNS, Bastion access to all hosts, private-only Key Vault and CycleCloud access, no direct public VM ingress, and no exposed secret values.

### Tests for User Story 1

- [X] T016 [P] [US1] Add Terraform composition tests asserting one feature resource group, `vnet-source` and `vnet-burst` in distinct configured regions, bidirectional global peering, dedicated management/burst/private-endpoint subnets, exactly three persistent private VMs in the source region, one source-region Bastion host, one private Key Vault endpoint, and one Log Analytics workspace in `tests/terraform/infrastructure.tftest.hcl`
- [X] T017 [P] [US1] Add security policy tests for explicit least-privilege NSG flows, default-denied unsolicited cross-subnet traffic, no public host or CycleCloud endpoint, Key Vault public access disabled, Entra group RBAC, managed identities, controlled outbound rules, and 90-day diagnostics in `tests/policy/test_network_security.py`
- [X] T018 [P] [US1] Add post-provision integration checks for private DNS from both VNETs, approved peering flows, denied unauthorized flows, Bastion SSH/RDP reachability, failed public probes, private Key Vault resolution, and secret-free inventory in `tests/end-to-end/verify_infrastructure.sh`

### Implementation for User Story 1

- [X] T019 [P] [US1] Compose the feature resource group and Log Analytics workspace with pinned `Azure/avm-res-resources-resourcegroup/azurerm` `0.4.0` and `Azure/avm-res-operationalinsights-workspace/azurerm` `0.5.1`, including exactly 90-day retention, in `terraform/monitoring.tf`
- [X] T020 [US1] Compose `vnet-source` and `vnet-burst` in the configured distinct regions, dedicated subnets, bidirectional global peering, and private DNS links to both networks with pinned virtual-network `0.22.2` and private-DNS-zone `0.5.0` AVMs in `terraform/network.tf`
- [X] T021 [US1] Compose pinned network-security-group `0.6.0`, Bastion `0.9.0`, private Key Vault `0.11.0`, private endpoint/DNS, Entra group RBAC, managed-identity access, approved egress, and diagnostic settings in `terraform/security.tf`
- [X] T022 [US1] Compose private CycleCloud `8.9.3`, supported AlmaLinux HPC scheduler, and supported Windows Server administration VMs with pinned virtual-machine `0.21.0` AVM calls, no public IPs, pinned image plan metadata, sufficient sizes, managed identities, and minimal Chef bootstrap in `terraform/compute.tf`
- [X] T023 [US1] Emit only private host names and addresses, source and burst regions, Bastion/application access instructions, pinned image and product identifiers, cluster name, and validation references as nonsensitive inventory while marking every credential-bearing value sensitive in `terraform/outputs.tf`
- [X] T024 [US1] Wire validation, reviewed-plan digest capture, exact saved-plan apply, 90-minute provisioning timing, and retry-safe inventory generation into `tests/end-to-end/provision.sh`

**Checkpoint**: The secure Azure foundation is independently provisionable and verifiable.

---

## Phase 4: User Story 2 - Prepare the Headless Slurm Environment (Priority: P1)

**Goal**: Converge CycleCloud and the external scheduler twice without changes on the second run, safely generate a release-matched headless template, and import one consistently named cluster.

**Independent Test**: Run both Chef policies twice; verify zero second-run updates, discovered and recorded versions, exact Slurm/Munge identities, absence of all prohibited sections, preserved last-valid output on every failure, valid imported cluster, matching storage/OS/identity settings, and no secret leakage.

### Tests for User Story 2

- [X] T025 [P] [US2] Add processor contract tests for clean and already-transformed sources, repeated no-op execution, matching/conflicting identities, each independently absent removable section, duplicate/malformed nesting, validator rejection, permission failure, interrupted write, digest/status output, temporary-file cleanup, and preserved last-valid destination in `tools/headless_template/tests/test_transform.py`
- [X] T026 [P] [US2] Add processor boundary tests proving exit codes `2` through `6`, structured secret-free output, safe distinct source/destination paths, explicit validator-only subprocess capability, and no Azure SDK, Terraform, or deployment imports in `tools/headless_template/tests/test_contract.py`
- [X] T027 [P] [US2] Add Chef unit tests for pinned non-interactive CycleCloud installation, private TLS, CLI/project discovery, compatibility failure, processor invocation, validation/import, cluster access, redaction, and change-only notifications in `chef/cookbooks/cyclecloud_node/test/unit/recipes/default_test.rb`
- [X] T028 [P] [US2] Add Chef unit tests for conflicting identity rejection, exact Slurm/Munge versions and IDs, NFS exports, demonstration-user identity, private CycleCloud integration, disabled return proxy, validation-before-service-start, redaction, and change-only notifications in `chef/cookbooks/slurm_scheduler/test/unit/recipes/default_test.rb`
- [X] T029 [P] [US2] Add InSpec controls for CycleCloud `8.9.3`, trusted private TLS, discovered project inventory, imported cluster, UID/GID `11100`, Munge UID/GID `11101`, `/sched` and `/shared`, package/service state, file permissions, private endpoints, and absence of secrets in known logs in `chef/test/integration/cyclecloud/controls/default.rb` and `chef/test/integration/scheduler/controls/default.rb`
- [X] T030 [P] [US2] Add a two-converge harness that fails unless the second CycleCloud and scheduler Chef Local runs report zero updates and the second processor run reports `changed=false` in `chef/test/integration/idempotency/verify.sh`

### Implementation for User Story 2

- [X] T031 [P] [US2] Implement the `headless-template transform` CLI, argument/path validation, documented exit codes, structured status and digest output, and actionable secret-free diagnostics in `tools/headless_template/src/headless_template/cli.py`
- [X] T032 [US2] Implement bracket-depth structural parsing that rejects malformed, duplicate, nested-incorrect, ambiguous, missing, and conflicting target structures while preserving untargeted bytes and ordering in `tools/headless_template/src/headless_template/parser.py`
- [X] T033 [US2] Implement the exact identity insertion (`slurm` UID/GID `11100`, `munge` UID/GID `11101`) and exact 13-section removal set from the processor contract in `tools/headless_template/src/headless_template/transform.py`
- [X] T034 [US2] Implement validator-before-write behavior, equal-content no-op, same-directory restricted temporary files, flush and atomic replacement, permission preservation, cleanup, and last-valid-destination preservation in `tools/headless_template/src/headless_template/writer.py`
- [X] T035 [P] [US2] Define CycleCloud attributes for exactly version `8.9.3`, private name/certificate references, stable cluster name, protected credentials, discovered project/template paths, version inventory, and Chef policy pinning in `chef/cookbooks/cyclecloud_node/attributes/default.rb`
- [X] T036 [US2] Implement pinned CycleCloud installation, private certificate retrieval and chain configuration, non-interactive CLI setup, installed Slurm project/version discovery, fail-closed compatibility checks, source fetch, processor validation, and one-cluster import in `chef/cookbooks/cyclecloud_node/recipes/default.rb`
- [X] T037 [P] [US2] Define scheduler attributes for the pinned AlmaLinux HPC image, stable cluster name, acceptance partition, positive idle timeout, scheduler private address, exact shared paths `/sched` and `/shared`, direct-peering return proxy disabled, exact one-node limit, protected credential references, and consistent demonstration-user identity in `chef/cookbooks/slurm_scheduler/attributes/default.rb`
- [X] T038 [US2] Implement conflict-safe Slurm/Munge identities, exact discovered Slurm package version, scheduler-hosted NFS, consistent demonstration user/home/key, project-matched `azslurm`, private CycleCloud authentication, return-proxy disablement, config validation, and ordered Munge/NFS/Slurm service enablement in `chef/cookbooks/slurm_scheduler/recipes/default.rb`
- [X] T039 [P] [US2] Create CycleCloud and scheduler configuration templates with restricted permissions and consistent cluster, endpoint, partition, storage, OS-family, identity, and one-node settings in `chef/cookbooks/cyclecloud_node/templates/default/cluster.properties.erb` and `chef/cookbooks/slurm_scheduler/templates/default/slurm.conf.erb`
- [X] T040 [US2] Add protected Chef Local convergence entry points that retrieve secrets through managed identity or an approved bootstrap channel, redact sensitive values, remove temporary secret files, record discovered versions, and return nonzero on authentication or compatibility failures in `chef/bin/converge-cyclecloud.sh` and `chef/bin/converge-scheduler.sh`

**Checkpoint**: The headless cluster and external scheduler are reproducibly configured with no-op reruns.

---

## Phase 5: User Story 3 - Demonstrate an End-to-End Burst Job (Priority: P1)

**Goal**: Submit one job from the scheduler, create exactly one remote compute node, write node-identifying output to shared storage, and remove the node after the configured idle timeout.

**Independent Test**: As the demonstration user, submit the hello-world job and verify within 15 minutes that exactly one node in the configured burst region runs it, shared output identifies that node and region while the scheduler remains in the source region, mounts and ownership are correct, and the node is later removed while the scheduler remains usable.

### Tests for User Story 3

- [X] T041 [P] [US3] Add the one-node Slurm acceptance job that writes its execution hostname and job metadata under `/shared/home/<username>` in `tests/end-to-end/fixtures/burst-job.sh`
- [X] T042 [P] [US3] Add assertions for queued/configuring/running/completed transitions, exactly one CycleCloud-created node in `burst_region`, scheduler placement in `source_region`, shared `/sched` and `/shared` mounts, consistent UID/GID and ownership, remote hostname/region evidence, 15-minute completion, idle-timeout removal, and scheduler continuity in `tests/end-to-end/verify_burst_job.sh`
- [X] T043 [P] [US3] Add repeated clean-run evidence collection for the required first-submission success rate while classifying documented regional-capacity failures separately in `tests/end-to-end/reliability.sh`

### Implementation for User Story 3

- [X] T044 [US3] Configure the acceptance partition and node array for the selected `burst_region`, matching compute OS family, scheduler-private cross-region NFS endpoints, exactly one maximum acceptance node, direct global-peering networking, and operator-configurable idle timeout in `chef/cookbooks/cyclecloud_node/templates/default/slurm-headless-overrides.txt.erb`
- [X] T045 [US3] Implement demonstration-user provisioning with a stable configurable nonprivileged name, the same unused UID/GID on scheduler and compute nodes, home `/shared/home/<username>`, Key-Vault-held private key, public-key authorization, and cluster-only access in `chef/cookbooks/slurm_scheduler/recipes/demo_user.rb`
- [X] T046 [US3] Implement the end-to-end submission, bounded polling, explicit failure diagnostics, output capture, node-lifecycle capture, and secret-free evidence bundle in `tests/end-to-end/run_burst_demo.sh`

**Checkpoint**: The core cloud-bursting outcome is independently demonstrated end to end.

---

## Phase 6: User Story 4 - Access and Operate CycleCloud Privately (Priority: P2)

**Goal**: Reach the Windows administration host through Bastion, trust and open CycleCloud by private name, authenticate, and inspect the imported cluster and node state without public exposure.

**Independent Test**: From a Bastion RDP session, open the private CycleCloud URL without a certificate warning, authenticate with an authorized identity, locate the imported cluster and node status within five minutes, and confirm an untrusted public client cannot connect.

### Tests for User Story 4

- [X] T047 [P] [US4] Add Windows InSpec controls for the CycleCloud private-name DNS result, installed private issuer chain, certificate name/chain validity, no public route, and no stored plaintext application credentials in `chef/test/integration/windows_admin/controls/private_access.rb`
- [X] T048 [P] [US4] Add the operator acceptance procedure and evidence checks for Bastion RDP, private browser access, authorized authentication, cluster/node inspection within five minutes, and denied public access in `tests/end-to-end/verify_private_administration.ps1`

### Implementation for User Story 4

- [X] T049 [US4] Implement Windows guest configuration for Key Vault certificate-chain retrieval, trusted issuer installation, private CycleCloud DNS verification, and browser readiness without embedding credentials in `chef/cookbooks/windows_admin/recipes/default.rb`
- [X] T050 [US4] Add the pinned Windows administration cookbook metadata and Policyfile used by the VM bootstrap in `chef/cookbooks/windows_admin/metadata.rb` and `chef/policyfiles/windows_admin.rb`
- [X] T051 [US4] Add secret-free operator instructions for Bastion RDP, private CycleCloud URL access, authorized application authentication, cluster inspection, and certificate/public-access troubleshooting in `README.md`

**Checkpoint**: Private graphical administration is independently verifiable.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Complete compliance evidence, documentation, and whole-system validation across all selected stories.

- [X] T052 [P] Document the Python exception rationale, inputs, outputs, native-parser limitation, exact transformation, validator, exit codes, atomic/no-op behavior, and failure preservation guarantees in `tools/headless_template/README.md`
- [X] T053 [P] Add audit queries and evidence export for secret access, administrative sign-in, configuration, cluster import/start, node lifecycle, and job completion with exactly 90-day retention and no secret values in `tests/end-to-end/collect_audit_evidence.sh`
- [X] T054 [P] Add inventory validation against the shared schemas and checks for private names/addresses, application instructions, pinned versions, cluster name, plan digest, validation references, and absence of secret values in `tests/end-to-end/verify_inventory.py`
- [X] T055 Add the complete operator workflow for preflight, validation, saved-plan review, exact-plan apply, Chef convergence, private administration, burst-job acceptance, audit review, retry behavior, and fail-stop rules in `README.md`
- [ ] T056 Run and record the complete quickstart validation sequence, including a second no-change Terraform plan, two zero-change Chef reruns, processor no-op, public-exposure probes, secret scans, one-node job evidence, node teardown, and audit review in `tests/evidence/quickstart-results.json`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: Starts immediately.
- **Phase 2 (Foundational)**: Depends on Phase 1 and blocks every user story.
- **Phase 3 (US1)**: Depends on Phase 2.
- **Phase 4 (US2)**: Code and tests can begin after Phase 2; its deployed independent test requires the private hosts and networking delivered by US1.
- **Phase 5 (US3)**: Depends on completed US1 and US2 because the job requires provisioned infrastructure, the imported headless cluster, and the configured scheduler.
- **Phase 6 (US4)**: Depends on US1 for Bastion/Windows/private networking and US2 for an imported cluster to inspect.
- **Phase 7 (Polish)**: Depends on all stories selected for the release.

### User Story Dependency Graph

```text
Setup -> Foundational -> US1 --------> US2 -> US3
                            \           \
                             -----------> US4
```

- **US1 (P1)**: First independently deployable increment and suggested MVP.
- **US2 (P1)**: Independently testable on the US1 foundation; does not require US3 or US4.
- **US3 (P1)**: Principal business outcome; integrates US1 and US2.
- **US4 (P2)**: Optional graphical administration increment; does not block US3.

### Within Each User Story

- Write tests first and confirm they fail for the intended missing behavior.
- Implement data/configuration declarations before recipes, scripts, and integration wiring that consume them.
- Validate generated configuration before enabling dependent services.
- Complete each story's independent test before starting a dependent story.

## Parallel Opportunities

- **Setup**: T003, T004, T005, and T006 can run in parallel after T001.
- **Foundational**: T009 through T013 can run in parallel after shared inputs/naming are defined.
- **US1**: T016-T018 can run in parallel; T019 can run while T020-T022 are prepared in dependency order.
- **US2**: T025-T030 can run in parallel; T031, T035, T037, and T039 affect separate files and can run in parallel before their dependent implementations.
- **US3**: T041-T043 can run in parallel before T044-T046.
- **US4**: T047 and T048 can run in parallel before T049-T051.
- **Polish**: T052-T054 can run in parallel before the final workflow and recorded acceptance run.

## Parallel Examples

### User Story 1

```text
Task T016: Terraform composition tests in tests/terraform/infrastructure.tftest.hcl
Task T017: Network security policy tests in tests/policy/test_network_security.py
Task T018: Provisioned-environment checks in tests/end-to-end/verify_infrastructure.sh
```

### User Story 2

```text
Task T025: Processor transformation and safety tests
Task T027: CycleCloud Chef unit tests
Task T028: Scheduler Chef unit tests
Task T029: CycleCloud and scheduler InSpec controls
Task T030: Two-converge idempotency harness
```

### User Story 3

```text
Task T041: One-node Slurm job fixture
Task T042: Burst-job lifecycle assertions
Task T043: Clean-run reliability evidence
```

### User Story 4

```text
Task T047: Windows private-access InSpec controls
Task T048: Private-administration acceptance procedure
```

## Implementation Strategy

### MVP First: Secure Foundation (US1)

1. Complete Setup and Foundational phases.
2. Complete US1 tests and implementation.
3. Provision a clean approved scope and pass the US1 independent test.
4. Stop for security, plan, and compliance review before adding guest integration.

### Core Demonstration

1. Add US2 and pass processor, Chef, compatibility, and second-converge gates.
2. Add US3 and pass the one-node job, shared-output, and teardown acceptance path.
3. Treat Setup + Foundational + US1 + US2 + US3 as the complete P1 demonstration.

### Incremental Delivery

1. Add US4 only after the command-line burst path works; verify private GUI access independently.
2. Complete cross-cutting audit, inventory, documentation, and full quickstart evidence.
3. Never bypass a failed preflight, validation, idempotency, private-connectivity, identity, certificate, secret-access, or plan-review gate.

---

## Phase 8: Convergence

- [X] T057 Define separate exact-version `scheduler_image` and `burst_compute_image` inputs, role-specific validation, and example values in `terraform/variables.tf` and `terraform/environments/demo.tfvars.example` per FR-005 and FR-034 (missing)
- [X] T058 Wire the pinned burst-compute image through CycleCloud Chef attributes and the generated burst node-array configuration while retaining the scheduler image only for the source-region scheduler VM per FR-018 and FR-034 (missing)
- [X] T059 Extend `tests/end-to-end/preflight.sh` to validate each role's image in its assigned region against its assigned VM size and to fail on incompatible AlmaLinux family or major-release combinations without substitution per FR-032, FR-034, and SC-012 (partial)
- [X] T060 Add Terraform, Chef template, and preflight tests that prove independent scheduler and burst-compute image pins, correct role wiring, and explicit rejection of missing, unavailable, size-incompatible, or OS-incompatible image combinations per FR-034 and SC-012 (partial)
- [X] T061 Record both role-specific image URNs and compatibility results in Terraform inventory, shared schemas, inventory verification, and acceptance evidence per FR-027, FR-034, and SC-010 (partial)
- [X] T062 Align `research.md`, `data-model.md`, `contracts/node-configuration.md`, `quickstart.md`, and operator documentation with the separate scheduler and burst-compute image decision and its fail-stop validation procedure per the plan product-compatibility decision (partial)

---

## Phase 9: Convergence

- [X] T063 CRITICAL correct `tests/end-to-end/provision.sh` and its tests so provisioning consumes only an existing exact reviewed saved plan, verifies its digest and bound preflight evidence before apply, and never regenerates the approved plan per SC-002 and Constitution V (contradicts)
- [X] T064 Add validated `burst_zone`, ordered approved alternate region/zone candidates, and planned role-count inputs and examples in `terraform/variables.tf`, `terraform/environments/demo.tfvars.example`, and Terraform tests, then wire the selected zone into the CycleCloud burst node-array configuration per FR-037 and FR-040 (missing)
- [X] T065 Extend `tests/end-to-end/preflight.sh` to calculate required vCPUs for every planned role, compare total regional and VM-family quota usage and limits, preserve full SKU restriction metadata, validate exact zone eligibility, and assess each approved alternate candidate without substitution per FR-035, FR-036, and FR-040 (partial)
- [X] T066 Create an isolated AVM-only Terraform capacity-probe root using the exact burst region, zone, VM size, and image with private networking, no public ingress, ownership and expiry tags, and independent state in `terraform/capacity-probe/` per FR-038, FR-039, and Constitution II–IV (missing)
- [X] T067 Add the explicitly acknowledged, exact-plan capacity-probe apply and destroy procedure, bounded timeout, Azure allocation-error classification, cleanup verification, evidence capture, and full-validation restart after alternate selection in `tests/end-to-end/` and operator entry points per FR-038–FR-041 (missing)
- [X] T068 Extend Terraform outputs, `tests/schemas/inventory.schema.json`, `tests/end-to-end/verify_inventory.py`, and provisioning gates with selected region/zone quota measurements, restriction classifications, candidate assessments, probe timestamps and outcome, point-in-time disclaimer, and verified cleanup per FR-042 and SC-013–SC-016 (partial)
- [X] T069 Add deterministic preflight, Terraform, capacity-probe lifecycle, schema, and provisioning tests for sufficient and insufficient total/family quota, subscription/location/zone restrictions, eligible and inconclusive alternates, allocation success/failure/timeout, stale evidence, and cleanup failure per SC-013–SC-016 (partial)
- [X] T070 Update `README.md`, the repository quickstart, and evidence guidance with complete quota interpretation, explicit zonal placement, probe cost and temporal limitations, exact reviewed probe plans, cleanup remediation, alternate-candidate selection, and capacity-reservation guidance per the plan operator workflow (partial)

---

## Phase 10: CycleCloud Marketplace Deployment Boundary

- [X] T071 Amend the constitution, specification, research, plan, infrastructure contract, and operator workflow for the narrowly scoped CycleCloud VM-only Bicep deployment-stack exception and bounded Key Vault provisioning phase
- [X] T072 Replace the incompatible CycleCloud VM AVM call with a pinned standalone NIC AVM and a source-controlled Bicep template that declares the pinned Marketplace plan and required image data disk at LUN 0
- [X] T073 Add exact deployment-stack what-if, digest-bound approval, apply, reconciliation, evidence, and delete-all cleanup tooling with tests
- [X] T074 Add Key Vault provisioning `/32` inputs and a separately approved hardening-plan workflow that restores private-only access before acceptance
- [X] T075 Configure the pinned hotpatch Windows image with `AutomaticByPlatform` patch and assessment modes and add regression assertions
- [X] T076 Retain the exact-placement AlmaLinux HPC capacity probe and document that it validates burst SKU allocatability independently of the CycleCloud appliance
- [ ] T077 Run focused and full validation, record the architecture change, and restart source-bound acceptance only from the resulting commit
