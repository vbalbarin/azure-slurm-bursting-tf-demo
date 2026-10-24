# Administrative Password Generator CLI Contract

## Invocation

```text
python3 tests/end-to-end/generate_admin_passwords.py \
  --windows-password-file <absolute-protected-path> \
  --cyclecloud-password-file <absolute-protected-path> \
  --evidence-file <absolute-secret-free-path> \
  --lock-file <absolute-lock-path>
```

All four paths are required and must be distinct where they represent files with different
purposes. Parent directories must already exist and must not be group/world writable.

## Standard output and error

- Successful execution prints no password or password-derived data.
- Standard output may contain only a bounded status such as `generated` or `preserved`.
- Standard error may identify a policy rule, target label, path, or state code, but never a value,
  substring, hash, encoded value, or character position.
- Shell tracing must be disabled by callers.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Complete set generated or existing complete set preserved |
| `2` | Invalid invocation, unsafe path, or missing prerequisite |
| `3` | Partial credential set detected |
| `4` | Generated value failed policy or uniqueness validation |
| `5` | Lock unavailable because another generator is active |
| `6` | Protected write or evidence persistence failed |

All nonzero exits are fail-closed. The generator does not delete or overwrite an existing
credential in any failure path.

## New-set behavior

When neither credential exists:

1. Acquire the exclusive set lock.
2. Generate both values in memory.
3. Validate both values and their inequality.
4. Write mode-`0600` temporary files in each destination directory.
5. Flush, `fsync`, and atomically rename each absent target.
6. Validate final modes and values in memory.
7. Atomically write the secret-free evidence receipt.
8. Release the lock.

## Existing-set behavior

- If both credentials exist, require regular files at mode `0600`, compare them in memory for
  inequality, and emit a `preserved` receipt. Do not rewrite either file.
- If exactly one exists, return exit `3`; do not create, delete, chmod, or replace either file.
- Symlinks and nonregular credential paths are rejected.

## Test-only seams

Tests may inject a deterministic character source or an interruption immediately before the
second atomic replacement. These seams are unavailable through the production CLI and must never
accept a literal password argument.
