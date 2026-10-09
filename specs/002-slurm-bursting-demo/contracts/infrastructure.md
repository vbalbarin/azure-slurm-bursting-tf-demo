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
| CycleCloud version/image | Pinned to the planning decision and accepted Marketplace terms |
| Scheduler image | Exact-version standard AlmaLinux image available in the source region and compatible with the scheduler VM size |
| Burst-compute image | Independent exact-version AlmaLinux HPC image available in the burst region and compatible with the burst VM size |
| Windows image | Pinned supported Windows Server image |
| VM sizes | Available in region and meet vendor minimums |
| Cluster name and idle timeout | Stable valid name and positive duration |
| Sensitive credentials | Supplied through an approved sensitive channel; never ordinary files |

## Guarantees

1. Every Azure resource is created by a direct pinned AVM call.
2. `vnet-source` and `vnet-burst` have non-overlapping ranges in distinct recorded regions and
   bidirectional global peering.
3. Hosts, CycleCloud, and Key Vault have no public inbound endpoint.
4. Bastion is the administrative ingress path.
5. Key Vault public access is disabled; its private DNS resolves from both consuming networks.
6. NSG rules are explicit, least privilege, and default deny for unsolicited cross-subnet traffic.
7. Diagnostic destinations retain required records for 90 days.
8. Outputs contain inventory identifiers, private addresses, source and burst regions, but no
   secret values.

## Validation contract

Deployment is blocked unless:

- Formatting, initialization, validation, linting, and security policy checks succeed.
- The saved plan uses only approved provider and AVM sources.
- No direct resource block or local Terraform module is present.
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

## Failure behavior

Identical or unsupported regions, unavailable or role-incompatible image/SKU, insufficient total
or family quota, zonal restrictions, failed or inconclusive selected-placement capacity,
unconfirmed probe cleanup, cross-role OS incompatibility, unavailable global peering, overlapping
CIDR, denied Marketplace terms, absent AVM, or failed validation returns a nonzero result before
main-environment apply. The process must not substitute a different version, image, region, zone,
topology, or public endpoint automatically.
