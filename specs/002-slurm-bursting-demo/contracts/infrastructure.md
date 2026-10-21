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
| Key Vault policy-exclusion approval | Accountable digest-bound approval explicitly authorizing `SecurityControl=Ignore` on only the Key Vault during the provisioning window |
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
3. Hosts, CycleCloud, and Key Vault have no accepted public inbound endpoint. Bastion Standard is
   the sole interactive public ingress endpoint, and no VM NIC has a public IP.
4. Bastion permits portal/browser RDP only to the Windows administration VM. That VM is the jump
   host for SSH to the scheduler and CycleCloud hosts and HTTPS to the private CycleCloud
   application; Bastion has no direct SSH path to those Linux hosts.
5. Key Vault public access is disabled in the accepted environment; its private DNS resolves from
   both consuming networks. Neither the provisioning `/32` rule nor `SecurityControl=Ignore` can
   survive the hardening gate, and the exclusion is never applied to the resource group.
6. NSG rules are explicit, least privilege, and default deny for unsolicited cross-subnet traffic.
7. Diagnostic destinations retain required records for 90 days.
8. Outputs contain inventory identifiers, private addresses, source and burst regions, but no
   secret values.
9. A source-region Standard NAT Gateway serves only the access and management VM subnets. A
   distinct burst-region Standard NAT Gateway serves only the compute VM subnet. Each gateway has
   one managed Standard public IP; private-endpoint and Bastion subnets have no workload NAT
   Gateway association.

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
- Assertions prove that public IPs are limited to Bastion and the two outbound NAT Gateways, VM
  NICs have no public IPs, and Key Vault is private after provisioning.
- Live validation proves the access and management subnets reference the source NAT Gateway and
  the compute subnet references the distinct burst NAT Gateway.
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
- The exact foundation plan shows `SecurityControl=Ignore` only on the Key Vault, default-deny
  networking, and exactly one approved `/32`, and its approval explicitly authorizes the temporary
  exclusion.
- A separate exact Terraform hardening plan removes the provisioning `/32`, disables Key Vault
  public access, and removes `SecurityControl=Ignore` in the same apply before acceptance.
- The exact reviewed CycleCloud deployment-stack what-if is deployed only after its Terraform-owned
  NIC exists.

## Failure behavior

Identical or unsupported regions, unavailable or role-incompatible image/SKU, insufficient total
or family quota, zonal restrictions, failed or inconclusive selected-placement capacity,
unconfirmed probe cleanup, cross-role OS incompatibility, unavailable global peering, overlapping
CIDR, denied Marketplace terms, absent AVM, missing explicit approval for the temporary Key Vault
policy exclusion, a resource-group-wide exclusion, or failed validation returns a nonzero result
before main-environment apply. A CycleCloud what-if outside the VM-only boundary, an unapproved
Bicep digest, a surviving Key Vault provisioning rule or exclusion tag, or deployment-stack
cleanup failure returns a nonzero result. The process must not substitute a different version,
image, region, zone, topology, or public endpoint automatically.
