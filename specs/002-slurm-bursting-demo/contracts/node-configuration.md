# Node Configuration Contract

## Common Chef Local contract

- Cookbooks and Policyfiles are version-controlled and pinned.
- Runs are non-interactive and consume attributes through protected files or environment-specific
  inputs that do not expose secret values.
- Resources notify dependent services only when state changes.
- Two consecutive converges with unchanged inputs produce zero updates on the second converge.
- Failures return nonzero, identify the failed resource, and do not report convergence.
- Chef recipes do not create, mutate, or delete Azure control-plane resources.

## CycleCloud node outcome

The converged node must:

1. Run pinned CycleCloud 8.9.3 at a private DNS name with no public application ingress.
2. Present the Key Vault-held certificate and full trusted chain for that private name.
3. Provide the CycleCloud CLI non-interactively.
4. Discover and record installed Slurm project versions.
5. Fetch the selected project source and invoke the headless-template processor.
6. Validate and import one cluster with the configured stable cluster name.
7. Grant only the required demonstration-user cluster access.

## Scheduler node outcome

The converged node must:

1. Use the pinned supported AlmaLinux HPC image.
2. Define Slurm UID/GID `11100` and Munge UID/GID `11101`, rejecting conflicting identities.
3. Install the exact Slurm version discovered from the selected project.
4. Export `/sched` and `/shared` over only the required private network paths.
5. Maintain the demonstration user's consistent UID/GID, shared home, key, and authorization.
6. Install the project-matched external scheduler integration and configure the private CycleCloud
   URL, cluster name, and scheduler config directory.
7. Disable return proxy for healthy direct peering and use scheduler NFS for both shared paths.
8. Start and enable only the required Munge, NFS, and Slurm services after configuration validates.

## Sensitive-data contract

Chef may retrieve required values through the VM's managed identity or a protected bootstrap
channel. Sensitive properties must be marked, logs must redact values, temporary files must use
restricted permissions and be removed, and recipes must never place credentials in node attributes
that are emitted in ordinary reports.

## Verification

InSpec verifies identities, permissions, package versions, service state, NFS exports, private
endpoints, TLS trust, Slurm configuration, and absence of secrets from known logs and artifacts.
