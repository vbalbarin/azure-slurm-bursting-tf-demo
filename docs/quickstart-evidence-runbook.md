# Backend Bootstrap Evidence Runbook

Use this runbook only for a new approved backend-bootstrap acceptance run. The stopped run
`20261013T164853Z` is immutable and must never be resumed, amended, or reused.

## Evidence boundary

Create a new directory under `/evidence/quickstart/<new-run-id>/backend-bootstrap/` with mode
`0700`. Evidence must remain secret-free even inside the protected volume. Never record Terraform
state, state backups, plans, `.tfvars`, assertion inputs, Azure access tokens, credentials, raw
command output, or environment dumps. Preserve only bounded results, digests, schema-valid
secret-free outputs, approvals, timings, and validation summaries.

Bootstrap operational artifacts remain under `/state/terraform-backend/<environment>/`, not
`/evidence` or the Git workspace.

Terraform and Azure migration, provisioning, apply, unlock, and destroy commands are executed
directly by the accountable operator. Python acceptance tests validate only the resulting
schema-bound, secret-free evidence and must not invoke those commands or control-plane operations.

## Stages

1. **Source validation**: record the commit and clean Git status; run `make validate`,
   `make chef-style`, and `make chef-unit`. Stop on any failure.
2. **Bootstrap create/validate**: record mode, approved non-secret names, validation result,
   reviewed-plan digest, approval reference, apply result, elapsed time, and second no-change
   result. Do not preserve the plan.
3. **Preliminary readiness**: record schema-valid secret-free readiness output and its adjacent
   digest. Record each stable command ID, UTC time, exit status, bounded observation, execution
   context digest, and separately measured role-propagation delay.
4. **Migration and isolation**: record local/remote lineage and resource-count equality, remote
   pull result, no-change result, lock-conflict result, the three distinct keys, and confirmation
   that the protected local copy was retained until verification.
5. **Final readiness**: record schema-valid final evidence, adjacent digest, source commit,
   assessment interval, and confirmation that main and probe fail closed for negative fixtures.
6. **Replacement-operator recovery**: record group-based access, refreshed login, all three
   namespace initialization/read/lock results, elapsed recovery time, and confirmation that no
   shared credential was distributed.
7. **Managed removal**: record zero-resource dependent-state checks, reverse-migration result,
   local state mode/digest verification, separate unlock and destroy plan digests and approvals,
   stale/digest mismatch rejection, and final backend absence. Existing mode records that removal
   is prohibited.

Bootstrap acceptance must complete within 20 minutes excluding separately recorded Entra
role-propagation delay. Replacement-operator recovery must complete within 15 minutes. A failed
threshold, missing artifact, unexpected resource change, secret-shaped content, or Git-tracked
protected artifact stops the run.

Follow the exact commands and expected artifacts in
[`specs/003-terraform-backend-bootstrap/quickstart.md`](../specs/003-terraform-backend-bootstrap/quickstart.md)
and the operator workflow in [`README.md`](../README.md).
