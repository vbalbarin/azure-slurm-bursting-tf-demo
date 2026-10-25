# Governed Convergence Workflow Contract

## Entry point

The governed deployment workflow is the only remote dispatcher for initial scheduler convergence,
an identical-input retry, an approved update, or idempotency verification. It uses Azure VM Run
Command and requires the operator's existing Azure authorization. It never sends secret values in
the Run Command payload.

## Inputs

- Full source revision.
- CycleCloud and scheduler manifest digests.
- CycleCloud and scheduler node-specification digests.
- Expected VM resource IDs.
- Expected private CycleCloud URL and cluster name.
- Operation: `initial`, `retry`, `update`, or `verify-idempotency`.
- Protected evidence destination.

## Ordered protocol

1. **Inspect local receipts**
   - Read bounded state from both VMs.
   - Require exact source, manifest, and specification digest matches.
   - Reject any active role lock.

2. **Verify CycleCloud dependency**
   - Require `converged` or `idempotency_verified`.
   - Require the managed-identity provider and exactly one `cross-region-demo` cluster.
   - Require a valid secret-free CycleCloud convergence receipt.

3. **Verify scheduler readiness**
   - Require `environment_ready` or `waiting_dependencies` for initial dispatch.
   - Require Chef `18.11.11` and the exact scheduler policy release.
   - Verify the scheduler identity can obtain Key Vault metadata and the named secret without
     returning the value to the workflow.

4. **Authorize and invoke scheduler convergence**
   - Write a short-lived, non-secret authorization receipt containing operation and approved
     digests.
   - Invoke the local scheduler wrapper without secret arguments.
   - Collect only bounded state and secret-free evidence.

5. **Publish workload identity and enforce the manual gate**
   - Read `/shared/home/hpcuser01/.ssh/id_ed25519.pub` and its fingerprint through Run Command.
   - Reject malformed keys, unexpected UID/GID, or a fingerprint mismatch.
   - Emit a canonical, value-free scheduler public-identity receipt bound to approved source and
     specification digests and include its own SHA-256 digest.
   - Block burst-node creation until an operator completes
     `cyclecloud-user-ui-gate.md` and submits an accepted attestation matching the current receipt
     digest, source revision, specification digest, and public-key fingerprint.
   - Never invoke an undocumented CycleCloud user endpoint or datastore interface.

6. **Verify idempotency**
   - Invoke each converged role with `verify-idempotency`.
   - Require Chef success and exactly zero resources updated.
   - Record separate evidence; do not overwrite initial convergence evidence.

7. **Publish evidence**
   - Validate all JSON records against the feature schemas.
   - Scan for protected-value and private-key patterns.
   - Transfer evidence through the existing protected jump-host procedure.

## Retry contract

- `retry` is accepted only from `failed_retryable`.
- Attempt 1 and attempt 2 must have identical source, manifest, and specification digests.
- The workflow preserves both attempts' evidence.
- A second failure writes `replacement_required`.
- No operation may transition `replacement_required` back to a runnable state on the same VM.
- A changed digest requires the explicit `update` operation and cannot rehabilitate clean-boot
  evidence.

## Existing-VM update contract

- `update` accepts only a newly approved source, lock, manifest, specification, and bundle set.
- The workflow validates all inputs before sending the non-secret payload through Run Command.
- The role stages the release beside the current immutable release and atomically switches
  `/opt/slurm-demo/current` only after validation.
- The same role wrapper performs convergence and records distinct update evidence.
- Validation or convergence failure restores the prior `current` target, preserves the last valid
  release and failure evidence, and returns nonzero.
- No VM polls for, discovers, or applies an update without explicit governed dispatch.

## Failure behavior

Every failed gate or command returns nonzero, writes a bounded stage code, and leaves downstream
actions unexecuted. Missing or malformed receipts, digest mismatches, unauthorized secret access,
concurrent execution, a missing/rejected CycleCloud UI attestation, unexpected burst-node
identity, and nonzero idempotency updates are hard failures. Success-shaped fallback output is
prohibited.
