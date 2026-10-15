# Backend Lifecycle Contract

## Ownership modes

### Managed

The feature creates and owns the backend resource set. Every Azure change is represented by a
reviewed Terraform plan composed only from pinned AVM calls. The ordinary lifecycle is:

1. Validate source and protected inputs.
2. Initialize bootstrap with local state under `/state`.
3. Create and review a saved bootstrap plan.
4. Create an external plan-approval record from the generated plan digest.
5. Verify the approval record and digest immediately before applying only that saved plan.
6. Run direct read-only probes and native Terraform pre-migration readiness classification.
7. Preserve local state and its digest outside evidence.
8. Install the ignored AzureRM backend override.
9. Migrate local state to `<environment>/bootstrap.tfstate`.
10. Run direct remote state, no-change-plan, and lock-conflict commands.
11. Apply an exact reviewed output-only plan that records final native Terraform readiness.
12. Emit final readiness evidence plus its adjacent SHA-256 sidecar.
13. Initialize main and capacity-probe roots with their distinct keys.

### Existing

The feature accepts explicitly approved coordinates, creates no backend resources or assignments,
and validates applicable controls. It may create only the project's three state objects through
ordinary backend use. It never imports, mutates, locks, unlocks, or destroys organizational
resources.

## Approval boundaries

| Boundary | Required evidence |
|---|---|
| Managed create | Source validation, exact plan digest, approval reference |
| Remote migration | Pre-migration readiness, protected local-state digest, approval reference |
| Dependent initialization | Final readiness status `ready`, matching source and coordinate digest |
| Unlock | Empty/absent main and probe state, verified authoritative local bootstrap state, exact unlock-plan digest |
| Destroy | Verified local bootstrap state, unlocked backend, exact destroy-plan digest |

Changing source, input, state context, network mode, principal, coordinate, plan, or evidence digest
invalidates the applicable approval.

For create, unlock, and destroy, `plan_digest` is never a Terraform planning input. The required
order is:

1. generate the saved plan;
2. calculate its SHA-256 digest;
3. create and approve a record matching `backend-plan-approval.schema.json`;
4. verify the record, source commit, input digest, and plan digest immediately before apply;
5. apply that exact saved plan and allow Terraform to reject stale state.

## Migration rules

- Use `terraform init -migrate-state`, never `-reconfigure`, when state must be copied.
- Keep the protected source-state copy until destination state and a no-change plan are verified.
- Record only state digests in evidence; never copy state content into `/evidence`.
- A failed migration blocks dependent initialization or teardown.
- Reverse migration to `/state` is mandatory before managed unlock or destroy when bootstrap state
  was migrated to Azure Blob.
- An abandoned pre-migration deployment may be removed without first uploading state. It must
  record `state_migration_status = "never_migrated"`,
  `reverse_migration_verified = false`, and independently verify that the protected local state is
  authoritative. This cleanup does not satisfy local-to-remote-to-local acceptance.

## Removal rules

Managed removal is rejected unless:

1. main state exists or is explicitly verified absent and contains zero managed resources;
2. capacity-probe state exists or is explicitly verified absent and contains zero managed
   resources;
3. bootstrap state is verified in protected local state, either after reverse migration or because
   it never left the local backend;
4. an unlock plan is reviewed and applied;
5. a separate destroy plan is generated and reviewed.

Existing mode exposes no backend removal operation.

The pre-plan removal assessment matches `backend-lifecycle.schema.json`. It is separate from
ordinary readiness evidence and cannot add fields to `backend-readiness.schema.json`.
