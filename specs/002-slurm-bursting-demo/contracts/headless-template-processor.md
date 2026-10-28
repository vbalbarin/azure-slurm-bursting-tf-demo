# Headless Template Processor Contract

## Purpose and exception justification

The processor transforms only a CycleCloud Slurm cluster configuration file. CycleCloud provides
supported commands to fetch, build, upload, and import projects and templates but no standalone
template-validation command or supported public parser library for structural edits to its
nested-bracket DSL. This documented gap permits the Python exception under constitution v2.0.0.

## Command contract

```text
headless-template transform \
  --source <slurm.txt> \
  --destination <slurm-headless.txt> \
  --slurm-project-version <registered-project-version> \
  --validator <approved-headless-structural-validation-command>
```

The validator MUST reject a candidate that is not structurally complete and already transformed.
The subsequent `cyclecloud import_cluster` command is the authoritative CycleCloud parse and
import gate.

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

Require exactly one `cyclecloud/slurm:default` and one `cyclecloud/slurm:execute` cluster-init
reference and pin both to `--slurm-project-version`. Missing, duplicate, or differently pinned
references fail validation.

## Safety invariants

1. Source and destination must differ; the source is read-only.
2. Section boundaries are determined structurally by bracket depth, not by unbounded text matching.
3. Missing, duplicate, nested-incorrect, or malformed target sections fail closed.
4. Existing required identity values must match exactly or fail as a conflict.
5. Slurm cluster-init references must resolve to the explicitly selected registered project
   version.
6. Untargeted content and ordering are preserved.
7. Candidate validation occurs before destination replacement.
8. Equal candidate and destination content produces no write.
9. A temporary file is created in the destination directory, flushed, permissioned, and atomically
   replaced only after validation.
10. Every failure preserves the last valid destination and removes temporary files.
11. The package has no Azure SDK, Terraform, deployment, or general command-execution capability
    beyond the explicit validator command supplied by Chef.

## Required tests

- Clean source transformation
- Already transformed source
- Repeated execution with unchanged inputs
- Existing matching and conflicting identity values
- Missing, duplicate, conflicting, and already-correct cluster-init project versions
- Every removable section independently absent
- Duplicate and malformed section headers
- Candidate validator rejection
- Destination permission failure
- Interrupted temporary write
- Digest and changed-status correctness
- Proof that no Azure or deployment dependency is imported
