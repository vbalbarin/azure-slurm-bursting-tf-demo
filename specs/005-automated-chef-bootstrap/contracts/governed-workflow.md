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

5. **Reconcile workload identity**
   - Read `/shared/home/hpcuser01/.ssh/id_ed25519.pub` and its fingerprint through Run Command.
   - Reject malformed keys, unexpected UID/GID, or a fingerprint mismatch.
   - Invoke the CycleCloud reconciliation wrapper with public key, UID/GID `11200`, cluster name,
     and approved digests.
   - Require the CycleCloud record and cluster access to match before marking the gate passed.

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

## Failure behavior

Every failed gate or command returns nonzero, writes a bounded stage code, and leaves downstream
actions unexecuted. Missing or malformed receipts, digest mismatches, unauthorized secret access,
concurrent execution, unexpected CycleCloud user state, and nonzero idempotency updates are hard
failures. Success-shaped fallback output is prohibited.
