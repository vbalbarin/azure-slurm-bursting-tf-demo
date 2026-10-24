# Quickstart: Validate Automated Chef Bootstrap

This guide is the acceptance path for the completed feature. It uses the active governed evidence
run and does not replace the repository's approval, cleanup, or protected evidence-transfer
procedures.

## Prerequisites

- Approved source commit and backend readiness evidence are current.
- Feature 004 has generated or preserved the protected administrator credential set and its
  value-free receipt is accepted.
- The operator is authenticated to the accepted tenant and subscription.
- Foundation infrastructure, private DNS, NAT, Key Vault, and VM identities exist.
- The protected run-state directory contains required deployment inputs but no generated role
  bundle from a different source revision.
- No role convergence or infrastructure mutation is running.

## 1. Run source validation

```bash
make validate
```

Expected:

- Terraform, Bicep, Python, shell, ChefSpec, Cookstyle, and contract checks pass.
- Both role manifests validate against
  `contracts/artifact-manifest.schema.json`.
- Both node specifications validate against
  `contracts/node-specification.schema.json`.

## 2. Build deterministic role bundles

```bash
tests/end-to-end/build_chef_policy_bundles.sh \
  --source-revision "$(git rev-parse HEAD)" \
  --output-dir "$RUN_STATE/chef-artifacts"
```

Run the same command a second time in a separate empty output directory and compare manifests and
bundle SHA-256 values.

Expected:

- CycleCloud and scheduler digests are identical across both builds.
- Each decoded cloud-init payload is at most 60,000 bytes.
- Manifests contain Chef `18.11.11`, CycleCloud Slurm `4.0.11`, and the approved vendor digests.
- Bundle and node-specification content contains no secret value or private key.

## 3. Plan and review infrastructure

Use the existing governed backend workflow to produce the foundation plan and CycleCloud Bicep
what-if from the approved commit.

Expected plan scope:

- Scheduler identity gains only Key Vault secret-read access.
- Scheduler custom data changes to the verified scheduler bootstrap payload.
- CycleCloud rendered custom data changes to the verified CycleCloud payload.
- No VM receives a public IP.
- No artifact storage account, Terraform provisioner, or Chef Server is created.

Stop if the plan proposes unrelated replacement or if custom-data digests do not match the built
manifests.

## 4. Validate a clean CycleCloud boot

Rebuild only the CycleCloud VM through the governed VM-stack procedure, without logging in or
repairing the guest.

Inspect bounded state:

```bash
az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$CYCLECLOUD_VM_NAME" \
  --command-id RunShellScript \
  --scripts 'cat /var/lib/slurm-demo/cyclecloud/state.json'
```

Expected:

- Cloud-init succeeds.
- State validates against `contracts/bootstrap-state.schema.json`.
- State is `converged`.
- CycleCloud first-run, provider validation, Slurm 4.0.11 project installation, transformed
  template validation, and exactly one `cross-region-demo` import succeeded.
- Temporary protected files are absent.

## 5. Validate scheduler staging and dependency blocking

Rebuild only the scheduler VM and inspect its bounded state before dispatch.

Expected:

- Chef, policy, wrapper, manifest, and node specification are staged and verified.
- State is `waiting_dependencies`.
- Slurm configuration has not been partially applied.
- No cloud-init loop, timer, or daemon is polling CycleCloud.

## 6. Dispatch governed scheduler convergence

```bash
tests/end-to-end/converge_linux_roles.sh \
  --run-context "$RUN_STATE/run-context.env" \
  --operation initial
```

Expected:

- CycleCloud, scheduler, and Key Vault gates pass before dispatch.
- Scheduler convergence configures Slurm, Munge, NFS, and release-matched `azslurm`.
- `hpcuser01` exists with UID/GID `11200`, home `/shared/home/hpcuser01`, and a preserved Ed25519
  key pair.
- The public key fingerprint, UID/GID, and `cross-region-demo` access match the CycleCloud
  application record.
- No protected value appears in Run Command output or evidence.

## 7. Prove idempotency

```bash
tests/end-to-end/converge_linux_roles.sh \
  --run-context "$RUN_STATE/run-context.env" \
  --operation verify-idempotency
```

Expected:

- Both Chef runs succeed with exactly zero resources updated.
- Evidence validates against `contracts/convergence-evidence.schema.json`.
- Initial and idempotency evidence are distinct and retained.

## 8. Exercise failure controls

In non-acceptance fixtures, test:

1. Policy digest mismatch fails before extraction.
2. Node-specification digest mismatch fails before Chef.
3. Scheduler dispatch before CycleCloud readiness is blocked.
4. Missing Key Vault authorization fails without exposing the secret.
5. A concurrent role lock rejects the second run.
6. First failure permits one identical-input retry.
7. Second identical-input failure produces `replacement_required`.
8. A changed-input request cannot be labeled a retry.
9. Interrupted and failed runs remove temporary protected files.

## 9. Complete burst acceptance

After the `hpc-user` gate passes, submit the existing bounded job as `hpcuser01`. Require one
CycleCloud-created burst node, matching UID/GID and shared-home access, successful output, clean
node termination, and the repository's final no-change Terraform plan.

Transfer the validated secret-free evidence through the protected Windows jump-host procedure in
`docs/quickstart-evidence-runbook.md`.
