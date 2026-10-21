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
- Azure CLI with Bicep and deployment-stack support
- Accepted CycleCloud Marketplace terms for pinned version 8.9.3
- Approved private CIDRs for `vnet-source` and `vnet-burst`
- Approved runner IPv4 `/32` for the bounded Key Vault provisioning phase
- Approved sensitive input channel for required bootstrap credentials and certificate material

> [!IMPORTANT]
> `operator_group_object_ids` requires at least one existing Microsoft Entra security-group object
> ID. Terraform grants that group `Key Vault Secrets Officer` on the demo vault. This is a
> vault-scoped secret data-plane assignment, not a requirement for the group to be subscription
> Owner or Contributor. The separate identity running Terraform must be able to create the
> infrastructure and role assignments. Subscription ownership alone does not automatically let a
> person read Key Vault secret values; the person must belong to the listed group or have another
> suitable vault data-plane assignment. Automated burst-job operation does not depend on the human
> group after configuration, but human secret administration and recovery do.

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

> [!IMPORTANT]
> CycleCloud does not make managed nodes implicitly zonal. This feature deliberately selects one
> burst zone for deterministic eligibility checks, allocation probing, and evidence. Zone pinning
> does not itself guarantee low compute or storage latency and can reduce allocation flexibility.
> Tightly coupled production workloads may additionally require RDMA-capable placement, proximity
> controls, and co-located high-performance storage. The cross-region scheduler-hosted storage in
> this one-node acceptance demo is not a production low-latency HPC storage architecture.

Before creating the main-environment plan, run the implementation-provided static preflight and
review its evidence. Source `tests/end-to-end/export_preflight_env.sh` with the protected `.tfvars`
path first so Terraform derives and `jq` exports the non-secret preflight inputs without manual
duplication. Review the shell-safe values displayed by the helper. Use
`tests/end-to-end/marketplace_terms.sh show` to inspect CycleCloud legal links and acceptance state.
Acceptance is a separate, persistent subscription-level action and requires an authorized operator
to invoke `accept` with `ACCEPT_MARKETPLACE_TERMS=yes`; it is never performed by export or ordinary
preflight. Preflight must separately report:

- Required vCPUs, current usage, limits, available quota, and projected remaining quota for total
  regional and applicable VM-family quotas.
- Exact image and SKU eligibility plus subscription, location, and zone restrictions.
- The selected burst region and zone and every operator-approved alternate candidate.

Render the resulting JSON with
`tests/end-to-end/render_preflight_summary.sh "$PREFLIGHT_RESULTS_FILE"` and save stdout as a
Markdown evidence file. Preview that file in VS Code to review the overall result, image
compatibility, role placement, both quota scopes, alternate placements, and every detected
blocker. The Markdown is a review aid; the source JSON remains the authoritative preflight
evidence.

Then explicitly acknowledge temporary probe cost and use
`tests/end-to-end/capacity_probe.sh` to create and review the isolated
`terraform/capacity-probe/` plan. Apply only that reviewed probe plan, verify one exact burst node
can be allocated, create and approve the separate destroy plan, and confirm cleanup within 15
minutes. The probe uses the exact AlmaLinux HPC burst image, SKU, region, and zone and is
independent of the CycleCloud appliance. Treat success as point-in-time evidence only. Stop if
allocation or cleanup fails.

If the selected placement fails, review the ordered alternate assessments. To choose an alternate,
edit the protected inputs and restart static preflight, capacity probe, plan review, and approval;
never carry forward evidence from the previous placement.

Initialize the `terraform/` root with the approved backend and environment inputs, then create a
saved plan. Supply the protected preflight JSON as `PREFLIGHT_RESULTS_FILE` and the cleaned probe
JSON as `CAPACITY_PROBE_RESULTS_FILE`. Approval records the digests of the plan and both evidence
files. Provisioning must reject stale, changed, incomplete, or placement-incompatible evidence and
must never regenerate the reviewed plan.

Review must confirm:

- Only pinned providers and direct pinned AVM module calls appear.
- No direct Azure resource or local custom Terraform module exists.
- No host or CycleCloud public endpoint is planned. Key Vault is limited to the approved runner
  `/32` during initial secret creation, and `SecurityControl=Ignore` appears only on the Key Vault
  under explicit approval.
- Exactly two VNETs and the required bidirectional peerings are planned.
- The VNETs are placed in the approved distinct source and burst regions and use global peering.
- Exactly two Terraform-owned persistent VMs, one Terraform-owned CycleCloud NIC, and one Bastion
  host are planned. The third persistent VM is reviewed through the separate Bicep what-if.
- The scheduler VM uses only the source-region scheduler image; the CycleCloud node array uses only
  the independently pinned burst-compute image.
- No unintended replacement or destruction appears.
- Sensitive values are redacted and absent from outputs.

Record the saved-plan digest and approval.

## 3. Apply the exact reviewed plan

Apply only the saved Terraform plan from step 2. Do not regenerate it between approval and apply.
Compile the CycleCloud Bicep source into protected state, derive its parameters from Terraform
outputs, and use `tests/end-to-end/cyclecloud_stack.sh` to validate and capture the exact what-if.
Approve its template, parameter, and what-if digests before deployment. Require exactly one
CycleCloud Marketplace VM with the Terraform-owned NIC and image data disk at LUN 0.

After initial secret creation, set Key Vault provisioning access to false and its IP rules to an
empty list. Generate, review, approve, and apply a separate Terraform hardening plan that also
removes `SecurityControl=Ignore`. Do not accept provisioning or begin guest convergence until Key
Vault reports `publicNetworkAccess=Disabled`, default deny, zero IP rules, and no policy-exclusion
tag.

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

Use Bastion RDP to connect to the Windows administration host. Bastion does not connect directly
to the Linux hosts. From the Windows jump host, use SSH for scheduler or CycleCloud host
administration and open the private CycleCloud name in a browser using HTTPS. Authenticate with
the authorized application identity.

Expected outcome:

- No certificate warning appears.
- The certificate matches the private name and chains to the installed trusted issuer.
- The imported headless cluster is visible.
- Direct access from an untrusted public client fails.

## 6. Submit the acceptance job

Connect to the scheduler from the Windows jump host as the demonstration user. Submit the
implementation's one-node hello-world job to the configured partition.

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
