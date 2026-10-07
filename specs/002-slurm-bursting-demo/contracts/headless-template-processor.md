# Headless Template Processor Contract

## Purpose and exception justification

The processor transforms only a CycleCloud Slurm cluster configuration file. CycleCloud provides
supported commands to fetch, validate, and import templates but no supported public parser library
for structural edits to its nested-bracket DSL. This documented gap permits the Python exception
under constitution v2.0.0.

## Command contract

```text
headless-template transform \
  --source <slurm.txt> \
  --destination <slurm-headless.txt> \
  --validator <approved-cyclecloud-validation-command>
```

Exit codes:

| Code | Meaning |
|---|---|
| `0` | Valid destination exists; output states `changed=true` or `changed=false` |
| `2` | Invalid arguments or unsafe path relationship |
| `3` | Source syntax or expected structure invalid |
| `4` | Required transformation is ambiguous |
| `5` | Candidate fails external validation |
| `6` | Safe write or atomic replacement fails |

Standard output contains only structured status, source digest, destination digest, changed flag,
and removed-section names. Standard error contains actionable diagnostics without file secrets.

## Required transformation

Add or verify under `[[node defaults]]` and `[[[configuration]]]`:

```text
slurm.user.name = slurm
slurm.user.uid = 11100
slurm.user.gid = 11100
munge.user.name = munge
munge.user.uid = 11101
munge.user.gid = 11101
```

Remove exactly:

- `[[node scheduler]]`
- `[[nodearray scheduler-ha]]`
- `[[nodearray login]]`
- `[[[parameter SchedulerMachineType]]]`
- `[[[parameter loginMachineType]]]`
- `[[[parameter NumberLoginNodes]]]`
- `[[[parameter SchedulerHostName]]]`
- `[[[parameter SchedulerImageName]]]`
- `[[[parameter LoginImageName]]]`
- `[[[parameter SchedulerClusterInitSpecs]]]`
- `[[[parameter LoginClusterInitSpecs]]]`
- `[[[parameter SchedulerZone]]]`
- `[[[parameter SchedulerHAZone]]]`

## Safety invariants

1. Source and destination must differ; the source is read-only.
2. Section boundaries are determined structurally by bracket depth, not by unbounded text matching.
3. Missing, duplicate, nested-incorrect, or malformed target sections fail closed.
4. Existing required identity values must match exactly or fail as a conflict.
5. Untargeted content and ordering are preserved.
6. Candidate validation occurs before destination replacement.
7. Equal candidate and destination content produces no write.
8. A temporary file is created in the destination directory, flushed, permissioned, and atomically
   replaced only after validation.
9. Every failure preserves the last valid destination and removes temporary files.
10. The package has no Azure SDK, Terraform, deployment, or general command-execution capability
    beyond the explicit validator command supplied by Chef.

## Required tests

- Clean source transformation
- Already transformed source
- Repeated execution with unchanged inputs
- Existing matching and conflicting identity values
- Every removable section independently absent
- Duplicate and malformed section headers
- Candidate validator rejection
- Destination permission failure
- Interrupted temporary write
- Digest and changed-status correctness
- Proof that no Azure or deployment dependency is imported
