# Phase 0 Research: Secure Slurm Bursting Demonstration

## Azure resource composition

**Decision**: Call published Azure Verified Modules directly from the Terraform root and pin exact
versions during implementation:

| Capability | AVM source | Researched version |
|---|---|---|
| Resource group | `Azure/avm-res-resources-resourcegroup/azurerm` | `0.4.0` |
| VNETs, subnets, peering | `Azure/avm-res-network-virtualnetwork/azurerm` | `0.22.2` |
| Network security groups | `Azure/avm-res-network-networksecuritygroup/azurerm` | `0.6.0` |
| Linux and Windows VMs | `Azure/avm-res-compute-virtualmachine/azurerm` | `0.21.0` |
| Bastion | `Azure/avm-res-network-bastionhost/azurerm` | `0.9.0` |
| Key Vault and private endpoint | `Azure/avm-res-keyvault-vault/azurerm` | `0.11.0` |
| Private DNS zones and links | `Azure/avm-res-network-privatednszone/azurerm` | `0.5.0` |
| Log Analytics | `Azure/avm-res-operationalinsights-workspace/azurerm` | `0.5.1` |

**Rationale**: These modules cover all required Azure resource types, including peering, VM
extensions, private endpoints, DNS links, diagnostics, and 90-day log retention. Direct root calls
satisfy the constitution; wrapper modules would be prohibited custom Terraform modules.

**Alternatives considered**: Direct `azurerm_*` resources and local wrapper modules were rejected
by the constitution. A separate firewall or managed NFS service was rejected as unnecessary for
the bounded demonstration.

**Sources**:

- <https://registry.terraform.io/namespaces/Azure>
- <https://github.com/Azure/terraform-azurerm-avm-res-network-virtualnetwork>
- <https://github.com/Azure/terraform-azurerm-avm-res-compute-virtualmachine>
- <https://github.com/Azure/terraform-azurerm-avm-res-keyvault-vault>

## Product versions and compatibility

**Decision**: Pin Azure CycleCloud `8.9.3`, the current generally available release identified
during planning. Discover the Slurm project installed with that image, record its exact version,
and independently pin the scheduler to
`almalinux:almalinux-x86_64:9-gen2:9.8.2026100501` and burst compute to
`almalinux:almalinux-hpc:9-hpc-gen2:9.8.202608110`. Require both role-specific images, assigned VM
sizes, and the discovered project template to pass compatibility preflight before configuration
proceeds.

**Rationale**: The specification requires current GA selection during planning and reproducible
deployment afterward. The general-purpose scheduler size and HB-series burst size have different
image support requirements even though both roles require a compatible AlmaLinux 9 family.
Microsoft documents external schedulers and AlmaLinux HPC, but its public headless walkthrough
uses an older fixed release combination. Failing closed on both actual pinned images, their
assigned regions and VM sizes, and the installed project avoids silently combining unsupported
versions.

**Alternatives considered**: Resolving "latest" during every deployment was rejected as
non-reproducible. Reusing the HPC image for the general-purpose scheduler was rejected because
image support is VM-size-specific. Pinning the older walkthrough combination was rejected because
it violates the clarified current-release requirement. Automatically substituting another image,
VM size, or Slurm project was rejected because it would bypass compatibility review.

**Sources**:

- <https://learn.microsoft.com/azure/cyclecloud/release-notes?view=cyclecloud-8>
- <https://learn.microsoft.com/azure/cyclecloud/how-to/bursting/setup-instructions-for-cloud-bursting?view=cyclecloud-8>
- <https://learn.microsoft.com/azure/virtual-machines/sizes/high-performance-compute/azure-hpc-vm-images>
- <https://github.com/Azure/cyclecloud-slurm/releases>

## Cross-region topology

**Decision**: Place CycleCloud, the external scheduler, Windows administration, Bastion, and the
management private endpoints in an explicit source region. Place transient Slurm compute in a
different explicit burst region. Connect `vnet-source` and `vnet-burst` with bidirectional global
VNET peering and link the required private DNS zones to both networks.

**Rationale**: Cross-region placement demonstrates the intended capacity strategy: retain the
scheduler and administration plane in one Azure region while consuming compute from another
operator-approved region with less constrained capacity. Global VNET peering keeps traffic on the
Microsoft backbone, and one Bastion deployment can administer VMs across supported peered VNETs.
Explicit inputs keep the deployment reproducible and auditable.

**Alternatives considered**: A simulated on-premises source was deferred as a future extension.
Single-region placement was rejected because it does not demonstrate regional capacity mobility.
Automatic region ranking, failover, and substitution were rejected because they would add
unrequired control-plane logic, weaken plan reproducibility, and blur the boundary between a
bounded demonstration and a production capacity broker.

**Sources**:

- <https://learn.microsoft.com/azure/networking/design-guide/cross-region>
- <https://learn.microsoft.com/azure/bastion/vnet-peering>
- <https://learn.microsoft.com/azure/cyclecloud/>

## Headless template transformation

**Decision**: Use the installed CycleCloud and project CLIs for discovery, fetch, import, and
validation. Use a dedicated Python processor only for structural removal and identity insertion in
the nested-bracket cluster-template DSL.

**Rationale**: CycleCloud exposes CLI operations and internally parses templates, but no supported
public parser library performs the required headless section transformation. The Python exception
is therefore necessary and remains limited to a node-consumed configuration file.

The processor will:

1. Parse section headers by bracket depth and preserve untouched text byte-for-byte where possible.
2. Require exactly one expected cluster structure and reject duplicate or malformed target
   sections.
3. Add or verify the Slurm and Munge identity properties.
4. Remove only the README-enumerated scheduler, scheduler-HA, login, and parameter sections.
5. Validate the candidate with the installed CycleCloud tooling before replacement.
6. Compare candidate and destination content, perform no write when equal, write a same-directory
   temporary file, and atomically replace only after successful validation.
7. Preserve the last valid file and return nonzero on every failure.

**Alternatives considered**: Regular-expression or line-oriented `sed` processing was rejected
because nested sections make ambiguous removal unsafe. A third-party parser was rejected because
none is supported by CycleCloud. Manual editing was rejected as non-repeatable.

**Sources**:

- <https://learn.microsoft.com/azure/cyclecloud/cluster-references/cluster-template-reference>
- <https://learn.microsoft.com/azure/cyclecloud/cluster-references/special-parsing>

## Guest configuration boundary

**Decision**: Terraform creates VMs and invokes only a minimal bootstrap through AVM-supported
custom data or VM extensions. Version-controlled Chef Local policy and cookbooks own subsequent
CycleCloud and scheduler convergence. Chef does not create or mutate Azure control-plane
resources.

**Rationale**: This cleanly implements the constitution's control-plane and guest-configuration
separation. Chef Local requires no Chef server and provides native idempotent resources. The
CycleCloud cookbook installs and configures the pinned service, private TLS certificate, CLI,
project discovery, headless template generation, and cluster import. The scheduler cookbook owns
Slurm/Munge identities, packages, NFS exports, demonstration identity, autoscaler integration,
services, and configuration.

**Alternatives considered**: Terraform provisioners and large cloud-init documents were rejected
because they obscure state and idempotency. Chef Server was rejected as unnecessary infrastructure.
The Chef Azure extension was rejected because it targets Chef Server bootstrap rather than local
mode.

## Secrets and identity

**Decision**: Use Entra ID and least-privilege RBAC for Azure and Key Vault. Disable Key Vault
public access and link its private endpoint DNS zone to both VNETs. Supply deployment-time
credentials through sensitive, non-output inputs or authorized Key Vault data-plane operations;
never write values into source, ordinary logs, inventory, or nonsensitive Terraform outputs.
Install the private CycleCloud certificate from Key Vault and place its trust chain on the Windows
host through managed guest configuration.

**Rationale**: This matches the clarified identity, networking, and certificate requirements while
allowing local credentials only where the products require them.

**Alternatives considered**: Public Key Vault access, public CycleCloud TLS, and universal local
administrator credentials were rejected for excess exposure. Entra-only guest access was not
selected because CycleCloud and the demonstration flow still require local product identities.

## Validation strategy

**Decision**:

- Terraform: `fmt -check`, `validate`, TFLint, Checkov, policy tests, and reviewed saved plan.
- Chef: Cookstyle, unit tests, Test Kitchen, InSpec, and two consecutive converges with zero
  updates on the second run.
- Python: pytest, Bandit, type checking, and tests for initial transform, already-correct input,
  repeated execution, missing section, duplicate section, malformed nesting, validator failure,
  interrupted temporary write, and atomic replacement.
- Environment: private connectivity and DNS tests, no-public-ingress assertions, secret-leak
  scans, certificate trust test, one-node job completion, node teardown, and audit evidence.

**Rationale**: These gates directly test the constitution rather than relying on successful
deployment as a proxy.

**Alternatives considered**: Syntax-only tests were rejected because they do not establish
security, idempotency, or end-to-end behavior.
