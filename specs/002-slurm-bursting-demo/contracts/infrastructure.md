# Infrastructure Contract

## Inputs

| Input | Required validation |
|---|---|
| Environment name | Azure-safe naming prefix |
| Subscription and tenant | Authorized target and Entra tenant |
| Region | Supports pinned images, SKUs, Bastion, private endpoints, and Log Analytics |
| On-premises and remote CIDRs | Private and non-overlapping |
| Operator group object IDs | Existing Entra groups; no individual broad grants |
| CycleCloud version/image | Pinned to the planning decision and accepted Marketplace terms |
| AlmaLinux HPC image | Pinned and compatible with discovered Slurm project |
| Windows image | Pinned supported Windows Server image |
| VM sizes | Available in region and meet vendor minimums |
| Cluster name and idle timeout | Stable valid name and positive duration |
| Sensitive credentials | Supplied through an approved sensitive channel; never ordinary files |

## Guarantees

1. Every Azure resource is created by a direct pinned AVM call.
2. The two named VNETs have non-overlapping ranges and bidirectional peering.
3. Hosts, CycleCloud, and Key Vault have no public inbound endpoint.
4. Bastion is the administrative ingress path.
5. Key Vault public access is disabled; its private DNS resolves from both consuming networks.
6. NSG rules are explicit, least privilege, and default deny for unsolicited cross-subnet traffic.
7. Diagnostic destinations retain required records for 90 days.
8. Outputs contain inventory identifiers and private addresses but no secret values.

## Validation contract

Deployment is blocked unless:

- Formatting, initialization, validation, linting, and security policy checks succeed.
- The saved plan uses only approved provider and AVM sources.
- No direct resource block or local Terraform module is present.
- Review finds no unintended replacement or deletion.
- Public-IP and public-Key-Vault assertions pass.
- The exact reviewed saved plan is applied.

## Failure behavior

Unsupported region, unavailable image/SKU, overlapping CIDR, denied Marketplace terms, absent AVM,
or failed validation returns a nonzero result before apply. The process must not substitute a
different version, region, topology, or public endpoint automatically.
