# Infrastructure Contract

## Inputs

| Input | Required validation |
|---|---|
| Environment name | Azure-safe naming prefix |
| Subscription and tenant | Authorized target and Entra tenant |
| Source region | Hosts management and scheduler resources; differs from burst region and supports all pinned persistent services, images, and SKUs |
| Burst region and zone | Hosts transient compute; differs from source region and supports the pinned compute image, exact SKU, zonal placement, quota, and global peering |
| Alternate burst placements | Ordered operator-approved region and zone candidates; advisory only |
| Planned role counts | Exact counts used to calculate total regional and VM-family vCPU requirements |
| Source and burst CIDRs | Private and non-overlapping |
| Operator group object IDs | Existing Entra groups; no individual broad grants |
| Provisioning runner CIDR | Exact approved IPv4 `/32`; used only during initial Key Vault secret creation |
| CycleCloud version/image | Pinned to the planning decision and accepted Marketplace terms |
| CycleCloud Bicep artifact | Source-controlled VM-only template from the approved source commit |
| CycleCloud SSH public key | Protected operator-approved public key; its private counterpart never enters source or evidence |
| Scheduler image | Exact-version standard AlmaLinux image available in the source region and compatible with the scheduler VM size |
| Burst-compute image | Independent exact-version AlmaLinux HPC image available in the burst region and compatible with the burst VM size |
| Windows image | Pinned supported Windows Server image |
| VM sizes | Available in region and meet vendor minimums |
| Cluster name and idle timeout | Stable valid name and positive duration |
| Sensitive credentials | Generated only in protected run state; scheduler public key and Windows password reach Terraform through sensitive environment variables; private keys and password reach Key Vault only through file-based data-plane writes |

## Guarantees

1. Every Azure resource except the CycleCloud Marketplace VM is created by a direct pinned AVM
   call. The CycleCloud VM is the sole resource owned by the approved Bicep deployment stack.
2. `vnet-source` and `vnet-burst` have non-overlapping ranges in distinct recorded regions and
   bidirectional global peering.
3. Hosts, CycleCloud, and Key Vault have no public inbound endpoint.
4. Bastion is the administrative ingress path.
5. Key Vault public access is disabled in the accepted environment; its private DNS resolves from
   both consuming networks. The provisioning `/32` rule cannot survive the hardening gate.
6. NSG rules are explicit, least privilege, and default deny for unsolicited cross-subnet traffic.
7. Diagnostic destinations retain required records for 90 days.
8. Outputs contain inventory identifiers, private addresses, source and burst regions, but no
   secret values.

## Validation contract

Deployment is blocked unless:

- Formatting, initialization, validation, linting, and security policy checks succeed.
- The saved plan uses only approved provider and AVM sources.
- No direct resource block or local Terraform module is present.
- The CycleCloud Bicep template compiles, contains only one VM resource, pins the approved
  Marketplace image and plan, declares the image data disk at LUN 0, and references the
  Terraform-owned NIC.
- The canonical CycleCloud deployment-stack what-if digest matches its approval and contains no
  resource outside the VM-only ownership boundary.
- Review finds no unintended replacement or deletion.
- Public-IP and public-Key-Vault assertions pass.
- Preflight proves each role-specific image exists in its assigned region, supports its assigned VM
  size's architecture and VM generation, and shares a compatible AlmaLinux family and major
  release with the other role.
- Preflight proves every role has sufficient total regional and applicable VM-family quota for its
  planned vCPUs and records usage, limits, requirements, and projected headroom.
- Preflight proves the exact burst SKU and image are eligible in the selected availability zone
  and classifies all subscription, location, zone, and quota restrictions.
- A separately reviewed one-node capacity probe passes for the exact selected burst placement,
  records point-in-time evidence and explicit cost acknowledgement, and verifies cleanup of all
  temporary resources.
- Every operator-approved alternate placement has an advisory assessment that identifies
  eligibility, quota headroom, probe status, and rejection or inconclusive reasons without
  changing deployment inputs.
- The exact reviewed saved plan is applied.
- The one-time secret writer accepts only mode-0600 protected files, passes file paths rather than
  values to Azure CLI, and records only versioned secret IDs and names.
- A separate exact Terraform hardening plan removes the provisioning `/32` and disables Key Vault
  public access before acceptance.
- The exact reviewed CycleCloud deployment-stack what-if is deployed only after its Terraform-owned
  NIC exists.

## Failure behavior

Identical or unsupported regions, unavailable or role-incompatible image/SKU, insufficient total
or family quota, zonal restrictions, failed or inconclusive selected-placement capacity,
unconfirmed probe cleanup, cross-role OS incompatibility, unavailable global peering, overlapping
CIDR, denied Marketplace terms, absent AVM, or failed validation returns a nonzero result before
main-environment apply, a CycleCloud what-if outside the VM-only boundary, an unapproved Bicep
digest, a surviving Key Vault provisioning rule, or deployment-stack cleanup failure returns a
nonzero result. The process must not substitute a different version, image, region, zone, topology,
or public endpoint automatically.
