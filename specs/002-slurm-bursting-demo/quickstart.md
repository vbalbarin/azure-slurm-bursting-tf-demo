# Quickstart Validation Guide

This guide describes the executable acceptance sequence after implementation. It does not replace
the reviewed Terraform plan or environment-specific runbook.

## Prerequisites

- Authorized Azure subscription and Entra operator group
- Distinct source and burst regions, an explicit burst availability zone, and an ordered list of
  approved alternate region/zone candidates
- Sufficient total regional and VM-family quota for the exact planned role counts
- Exact scheduler and burst-compute image URNs selected independently, with a shared AlmaLinux
  family and major release
- Terraform and project validation tools at the pinned versions
- Accepted CycleCloud Marketplace terms for pinned version 8.9.3
- Approved private CIDRs for `vnet-source` and `vnet-burst`
- Approved sensitive input channel for required bootstrap credentials and certificate material

Review [research.md](./research.md), [data-model.md](./data-model.md), and all files under
[contracts/](./contracts/) before proceeding.

## 1. Validate source

From the repository root, run the implementation-provided validation entry points for:

```text
terraform format and validation
Terraform lint and security policy
Chef style and unit tests
Test Kitchen/InSpec with a second no-change converge
Python type, security, unit, failure, and idempotency tests
```

Expected outcome:

- Every command succeeds.
- The second Chef converge reports zero updates.
- The second template transformation reports `changed=false`.
- Invalid template cases preserve the last valid destination.

## 2. Create and review the plan

Before creating the main-environment plan, run the implementation-provided static preflight and
review its evidence. It must separately report:

- Required vCPUs, current usage, limits, available quota, and projected remaining quota for total
  regional and applicable VM-family quotas.
- Exact image and SKU eligibility plus subscription, location, and zone restrictions.
- The selected burst region and zone and every operator-approved alternate candidate.

Then explicitly acknowledge temporary probe cost, create and review the capacity-probe plan, apply
only that reviewed probe plan, and verify one exact burst node can be allocated. Destroy all
probe-owned resources and confirm cleanup within 15 minutes. Treat success as point-in-time
evidence only. Stop if allocation or cleanup fails.

If the selected placement fails, review the ordered alternate assessments. To choose an alternate,
edit the protected inputs and restart static preflight, capacity probe, plan review, and approval;
never carry forward evidence from the previous placement.

Initialize the `terraform/` root with the approved backend and environment inputs, then create a
saved plan. Supply the protected preflight JSON as `PREFLIGHT_RESULTS_FILE`; provisioning must
reject it if either role-specific image differs from the Terraform inventory or compatibility did
not validate.

Review must confirm:

- Only pinned providers and direct pinned AVM module calls appear.
- No direct Azure resource or local custom Terraform module exists.
- No VM, CycleCloud endpoint, or Key Vault public endpoint is planned.
- Exactly two VNETs and the required bidirectional peerings are planned.
- The VNETs are placed in the approved distinct source and burst regions and use global peering.
- Exactly three persistent VMs and one Bastion host are planned.
- The scheduler VM uses only the source-region scheduler image; the CycleCloud node array uses only
  the independently pinned burst-compute image.
- No unintended replacement or destruction appears.
- Sensitive values are redacted and absent from outputs.

Record the saved-plan digest and approval.

## 3. Apply the exact reviewed plan

Apply only the saved plan from step 2. Do not regenerate it between approval and apply.

Expected outcome:

- Provisioning completes within 90 minutes.
- Inventory reports private names, private addresses, both role-specific image URNs, image
  compatibility, quota and zonal evidence, capacity-probe outcome and cleanup, assessed alternate
  placements, pinned versions, cluster name, validation references, source region, burst region,
  and burst zone without secret values.
- Public-inbound probes to all hosts, CycleCloud, and Key Vault fail.
- Private DNS resolves CycleCloud and Key Vault from authorized network locations.

## 4. Verify guest convergence

Run the implementation-provided Chef Local convergence entry point on the CycleCloud and scheduler
hosts, then run it again unchanged.

Expected outcome:

- First run converges both nodes.
- Second run reports zero updates.
- CycleCloud reports version 8.9.3.
- Installed Slurm project and Slurm versions match recorded inventory.
- The scheduler reports the pinned standard AlmaLinux image, and the generated node array reports
  the pinned AlmaLinux HPC burst image.
- The headless template satisfies the
  [processor contract](./contracts/headless-template-processor.md).
- Scheduler identities, services, `/sched`, `/shared`, and external integration satisfy the
  [node contract](./contracts/node-configuration.md).

## 5. Verify private administration

Use Bastion to connect to the Windows administration host. Open the private CycleCloud name in a
browser and authenticate with the authorized application identity.

Expected outcome:

- No certificate warning appears.
- The certificate matches the private name and chains to the installed trusted issuer.
- The imported headless cluster is visible.
- Direct access from an untrusted public client fails.

## 6. Submit the acceptance job

Connect through Bastion to the scheduler as the demonstration user. Submit the implementation's
one-node hello-world job to the configured partition.

Expected outcome within 15 minutes under normal regional capacity:

1. The job moves from queued to configuring/running.
2. One remote CycleCloud compute node appears.
3. The job completes on that node.
4. Output under the user's shared home names the execution node and proves it is in the configured
   burst region while the scheduler remains in the configured source region.
5. After the configured idle timeout, the compute node is removed.

## 7. Verify audit evidence and convergence

Confirm validation, administrative access, secret access, configuration, cluster lifecycle, and
job evidence is queryable without secret values and has 90-day retention.

Run a second Terraform plan with unchanged inputs.

Expected outcome:

- No unintended infrastructure change is proposed.
- Chef and processor reruns remain no-op.
- The audit package allows an independent reviewer to confirm every acceptance result.

## Failure rule

Stop immediately on validation, quota, zonal eligibility, selected-placement capacity,
probe-cleanup, compatibility, private connectivity, identity, certificate, secret-access,
idempotency, or plan-review failure. Do not substitute versions, regions, zones, expose a public
endpoint, bypass validation, or manually patch a node to continue the demonstration.
