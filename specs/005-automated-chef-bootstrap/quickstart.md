# Quickstart: Validate Automated Chef Bootstrap

This guide is the acceptance path for the completed feature. It uses the active governed evidence
run and does not replace the repository's approval, cleanup, or protected evidence-transfer
procedures.

## Prerequisites

- Approved source commit and backend readiness evidence are current.
- Feature 004 has generated or preserved the protected administrator credential set and its
  value-free receipt is accepted.
- The operator is authenticated to the accepted tenant and subscription.
- The authenticated deployment identity can read Microsoft Graph subscribed-SKU metadata, and a
  current value-free receipt proves the tenant has an enabled, successfully provisioned
  `AAD_PREMIUM` service plan.
- Foundation infrastructure, private DNS, NAT, Key Vault, independent locker UAMI, and the exact
  CycleCloud custom role definition exist.
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
- The CycleCloud identity/RBAC receipt fixtures validate against
  `contracts/cyclecloud-identity-rbac.schema.json`.

Static implementation checkpoint:

- Combined ChefSpec suite: 48 examples, 0 failures.
- Registered end-to-end Python suite: 142 passed, including 15 Entra preflight, 22 CycleCloud
  stack, and 34 Chef-bootstrap contract tests.
- Policy suite: 28 passed, including six backend secret-hygiene tests.
- Backend contract and evidence suites: 31 passed and two environment-dependent tests skipped.
- Terraform Chef-bootstrap identity lifecycle tests: 17 passed.
- Main Terraform suite: 39 passed; capacity-probe and backend-bootstrap suites: 8 and 32 passed.
- Both deterministic role bundles rebuilt successfully from their refreshed policy locks.
- Bicep build, Terraform validation/TFLint, Bash syntax, ShellCheck, Cookstyle, Python type/security
  checks, and the 15-test headless-template suite passed.
- Checkov reported 28 passed checks and one documented skip for the constitution-authorized exact
  Microsoft CycleCloud custom role.
- Full registered `make validate` passed.
- Licensed local InSpec validation passed for the CycleCloud, scheduler, and Windows administration
  profiles with zero errors or offenses; only non-blocking control title/description warnings
  remain. No Azure Test Kitchen run was attempted.

These are secret-free static results, not a substitute for the new governed Azure run in sections
4 through 12.

## 2. Generate or preserve administrative credentials

Run feature 004 in a new protected evidence context. Review its value-free receipt before any
plan or deployment.

Expected:

- New-run Windows and CycleCloud administrator credentials differ and satisfy feature 004.
- Only protected files and the accepted value-free receipt are retained.
- No existing VM is tested with a newly generated credential before that credential is deployed.

## 3. Build deterministic role bundles

```bash
tests/end-to-end/build_chef_policy_bundles.sh \
  --source-revision "$(git rev-parse HEAD)" \
  --output-dir "$RUN_STATE/chef-artifacts"
```

Run the same command a second time in a separate empty output directory and compare manifests and
bundle SHA-256 values.

Expected:

- CycleCloud and scheduler digests are identical across both builds.
- Each role contains its reviewed `*.lock.json`; the manifest policy revision equals the lock
  `revision_id`, and `policyLockSha256` matches the included lock file.
- Each decoded cloud-init payload is at most 60,000 bytes.
- Manifests contain Chef `18.11.11`, CycleCloud Slurm `4.0.11`, and the approved vendor digests.
- Bundle and node-specification content contains no secret value or private key.

## 4. Plan, review, and apply infrastructure

Use the existing governed backend workflow to produce the foundation plan from the approved
commit with post-create CycleCloud RBAC disabled.

Expected plan scope:

- The former CycleCloud control UAMI and its assignments are removed.
- The independent locker UAMI remains and has only `Storage Blob Data Reader` at the locker
  storage account.
- The exact Microsoft CycleCloud custom role definition is created or retained with only the
  approved burst subscription as its assignable scope.
- No CycleCloud orchestrator role assignment exists before the VM principal is created.
- Scheduler identity gains only Key Vault secret-read access.
- Scheduler custom data changes to the verified scheduler bootstrap payload.
- CycleCloud rendered custom data changes to the verified CycleCloud payload.
- Scheduler-to-CycleCloud API traffic is restricted to private TCP 443, burst-to-CycleCloud
  cluster traffic is restricted to private TCP 9443, and the scheduler private-DNS A record is
  visible from both VNets.
- No VM receives a public IP.
- No artifact storage account, Terraform provisioner, or Chef Server is created.

Stop if the plan proposes unrelated replacement or if custom-data digests do not match the built
manifests.

Apply only the exact reviewed foundation plan. Generate the CycleCloud Bicep what-if from the same
approved source and parameters. Require a `SystemAssigned` VM identity and no user-assigned
identity map, then apply only that approved stack artifact.

Immediately after VM creation, capture the VM principal and produce a second plan from the same
Terraform root with post-create CycleCloud RBAC enabled. The plan must derive the principal from
the exact VM resource and add only:

- the approved CycleCloud custom-role assignment at the burst subscription scope; and
- `Key Vault Secrets User` at the bootstrap vault scope.

Apply only that exact reviewed post-create plan. Validate the resulting value-free receipt against
`contracts/cyclecloud-identity-rbac.schema.json`. The plan/apply and receipt are a distinct
approval boundary from foundation and the Bicep stack.

Rebuild the Terraform-owned Windows jump host before its administrative login check. Rebuild the
Terraform-owned scheduler separately when its approved custom data is applied.

Expected:

- CycleCloud first boot remains blocked until the post-create assignments propagate.
- Management, locker user-delegation, and bootstrap secret-read capability checks all pass within
  30 minutes without emitting a SAS or secret value.
- The new Windows credential is deployed before the `windowsadmin` login check.
- The new CycleCloud credential is deployed before the `hpcadmin` login check.
- Both accepted login checks record only pass/fail labels and no credential values.

## 5. Validate a clean CycleCloud boot

For any replacement of a VM that already uses a system identity, first plan the same Terraform root
with post-create RBAC disabled. Apply only the exact reviewed plan that removes the old principal's
two assignments, verify their absence, and then delete the Bicep stack. Preserve the custom role,
locker UAMI, NIC, and private IP.

Create only the CycleCloud VM through the governed VM-stack procedure, apply its reviewed
post-create RBAC plan, and do not log in or repair the guest.

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
- The VM has exactly one system-assigned identity and zero user-assigned identities.
- The CycleCloud provider omits a user-assigned client ID and references the independent locker
  UAMI only as `LockerIdentity`.
- The identity/RBAC receipt remains schema-valid and bound to the observed VM principal.
- State validates against `contracts/bootstrap-state.schema.json`.
- State is `converged`.
- CycleCloud first-run, provider validation, Slurm 4.0.11 project upload, transformed template
  validation, registered project `4.0.9` cluster-init pinning, and exactly one
  `cross-region-demo` import from the transformed template succeeded.
- The imported vendor `hpc` nodearray uses the approved burst region, zone, subnet, locker
  identity, AlmaLinux image, VM size, external `/sched` and `/shared` NFS endpoints, and maximum
  one node. No built-in scheduler or login node exists.
- Temporary protected files are absent.

Measure the same remote state-inspection command for each persistent VM and require schema-valid
output in less than 60 seconds.

## 6. Validate scheduler staging and dependency blocking

Rebuild only the scheduler VM and inspect its bounded state before dispatch.

Expected:

- Chef, policy, wrapper, manifest, and node specification are staged and verified.
- State is `waiting_dependencies`.
- Slurm configuration has not been partially applied.
- No cloud-init loop, timer, or daemon is polling CycleCloud.

## 7. Dispatch governed scheduler convergence

```bash
tests/end-to-end/converge_linux_roles.sh \
  --run-context "$RUN_STATE/run-context.env" \
  --operation initial
```

Expected:

- CycleCloud, scheduler, and Key Vault gates pass before dispatch.
- Scheduler convergence installs Microsoft Slurm `26.05.4-1.el9` RPMs directly and installs
  `azure-slurm-pkg-4.0.11` separately with Python 3.11 and `--no-jetpack`.
- The restricted `/sched` and `/shared` exports use `no_root_squash`; the shared cluster
  `slurm.conf` is client-readable and resolves the scheduler through private DNS.
- Release-matched `azslurm` runs through absolute paths, and autoscale configuration is mode
  `0600` and owned by `slurm:slurm`.
- `hpcuser01` exists with UID/GID `11200`, home `/shared/home/hpcuser01`, and a preserved Ed25519
  key pair.
- A value-free scheduler public-identity receipt records UID/GID and the public-key fingerprint.
- No protected value appears in Run Command output or evidence.

## 8. Complete the governed CycleCloud user UI gate

Follow `contracts/cyclecloud-user-ui-gate.md` as an authenticated `hpcadmin` operator.

Expected:

- `hpcuser01` is a non-superuser with node access enabled, UID `11200`, and the scheduler public
  key.
- The `cross-region-demo` Access dialog grants non-administrative node-user access.
- The accepted attestation matches the current scheduler receipt digest, source revision,
  specification digest, and fingerprint and contains no protected values.
- If the UI requires an application password, the protected one-time value satisfies feature
  004's CycleCloud policy, requires reset, is discarded immediately, and appears nowhere in
  evidence.
- Burst-node creation remains blocked until the attestation is accepted.

## 9. Prove idempotency

```bash
tests/end-to-end/converge_linux_roles.sh \
  --run-context "$RUN_STATE/run-context.env" \
  --operation verify-idempotency
```

Expected:

- Both Chef runs succeed with exactly zero resources updated.
- Evidence validates against `contracts/convergence-evidence.schema.json`.
- Initial and idempotency evidence are distinct and retained.

In fixtures, build a newly approved role release and exercise the governed `update` operation.
Require side-by-side immutable staging, atomic `current` switching, separate update evidence, and
restoration of the prior release after injected validation or convergence failure.

## 10. Validate reboot safety

Capture state/evidence digests and attempt counters, reboot each successfully converged persistent
VM, and repeat the bounded state inspection.

Expected:

- Both VMs return to service without rotating credentials, importing another cluster, applying a
  policy, or incrementing convergence attempts.
- State remains schema-valid and remotely inspectable in less than 60 seconds.
- A subsequent explicit idempotency run still reports zero resources updated.

## 11. Exercise failure controls

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
10. A VM with a UAMI or a substituted principal is rejected before role assignment.
11. Missing Microsoft Entra ID P1 evidence blocks foundation approval.
12. Management, user-delegation, or secret-read propagation timeout blocks CycleCloud first-run.
13. VM deletion is rejected while its system-principal assignments remain.

## 12. Complete burst acceptance

After the `hpc-user` gate passes, submit the existing bounded job as `hpcuser01`. Require one
CycleCloud-created burst node with UID `11200`, matching key and shared-home access, a recorded
conflict-free primary GID, successful output, and clean node termination. Require both the final
Terraform no-change plan with post-create RBAC enabled and a final exact CycleCloud
deployment-stack what-if from the approved template and parameters.

Transfer the validated secret-free evidence through the protected Windows jump-host procedure in
`docs/quickstart-evidence-runbook.md`.
