# Headless Template Processor

CycleCloud can fetch, validate, and import its nested-bracket cluster-template format, but it does
not expose a supported public parser that can safely remove scheduler/login structures while
preserving unrelated content. This package is the narrowly scoped configuration-file exception
permitted by the project constitution. It has no Azure SDK, Terraform, deployment, or general
orchestration dependency.

## Contract

```text
headless-template transform \
  --source /path/to/slurm.txt \
  --destination /path/to/slurm-headless.txt \
  --validator '/usr/bin/env PYTHONPATH=/opt/slurm-demo/current/tools/headless_template/src python3 -m headless_template validate {candidate}'
```

The source and destination must differ. The processor parses headers by bracket depth, verifies
the exact Slurm UID/GID `11100` and Munge UID/GID `11101`, and removes only the 13 sections named
in the feature contract. The source is never modified. The `validate` subcommand rejects a
candidate unless it is structurally complete and already transformed. CycleCloud 8.9.3 does not
provide a separate template-validation CLI command, so `cyclecloud import_cluster` performs the
authoritative CycleCloud parse when the validated destination is imported.

Standard output is one JSON object containing `status`, SHA-256 source and destination digests,
`changed`, and removed section names. Exit codes are:

- `0`: a valid destination exists
- `2`: invalid arguments or unsafe paths
- `3`: malformed template syntax
- `4`: ambiguous, incomplete, duplicate, or conflicting structure
- `5`: the explicit external validator rejected the candidate
- `6`: safe write or atomic replacement failed

The candidate is written to a restricted same-directory temporary file, flushed, permissioned,
and passed to the explicit validator without a shell. Replacement uses an atomic rename only
after validation. Equal content produces `changed=false` and no write. Every failure removes the
temporary file and preserves the last valid destination.
