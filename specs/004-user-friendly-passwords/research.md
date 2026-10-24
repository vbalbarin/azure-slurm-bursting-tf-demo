# Phase 0 Research: User-Friendly Generated Passwords

## Target policy profiles

**Decision**: Apply one new-interactive-password profile to both Windows administrator and
CycleCloud application administrator credentials: exactly 16 characters, at least two characters
from each of uppercase, lowercase, digits, and `!@#$%^*()-_+=`. Use unambiguous source alphabets:
`ABCDEFGHJKLMNPQRSTUVWXYZ`, `abcdefghijkmnopqrstuvwxyz`, and `23456789`.

**Rationale**: The profile satisfies the stricter feature requirement and both target systems'
length/complexity expectations while excluding `/`, quotes, backslash, whitespace, backticks,
ambiguous `O/0/I/l/1`, and other typing-sensitive characters. Using the same safe special set
reduces operator error without reusing values.

**Alternatives considered**: Base64 was rejected because `/` is outside the documented CycleCloud
set and long values are difficult to type. All printable punctuation was rejected as
shell/JSON/keyboard sensitive. Dictionary passphrases were rejected because they introduce a word
list dependency and do not match the approved exactly-16-character requirement.

## Cryptographic generation

**Decision**: Use Python `secrets.choice` to select two characters from each required class, fill
the remaining eight positions from the combined alphabet, and shuffle with
`secrets.SystemRandom().shuffle`. Generate both credentials in memory and repeat the second
generation only if it equals the first.

**Rationale**: Python's `secrets` module uses the operating system cryptographic random source.
Constructing the mandatory class members guarantees policy compliance rather than relying on a
probabilistic retry. Secure shuffling prevents predictable class positions.

**Alternatives considered**: Modulo mapping raw random bytes was rejected because careless
implementations introduce bias. `random` was rejected as noncryptographic. Repeatedly generating a
free-form string until it happens to satisfy policy was rejected as unnecessarily variable and
harder to test.

## Existing and partial credential state

**Decision**: Acquire an exclusive lock for the credential set. If both files already exist,
preserve them byte-for-byte and report `preserved`; do not enforce the new usability profile
retroactively. If neither exists, generate and validate both. If exactly one exists, fail with
`partial_credential_set` without writing, deleting, or replacing either file.

**Rationale**: Preserving a complete legacy set satisfies the no-silent-rotation rule. Failing on a
partial set makes interruption explicit and avoids guessing whether a lone value was approved,
used, or safe to rotate.

**Alternatives considered**: Completing a partial set automatically was rejected because the lone
credential may come from an interrupted unapproved attempt. Regenerating both was rejected as
silent rotation. Rejecting all legacy values that do not meet the new profile was rejected because
the feature explicitly preserves existing deployed credentials.

## Protected writes and interruption

**Decision**: Create each new file in its destination directory with mode `0600`, flush and
`fsync`, then atomically replace the absent target. Keep the set lock until both files and the
value-free evidence receipt are durable. If interruption occurs after one rename, the next run
detects partial state and fails for operator review.

**Rationale**: There is no portable atomic rename of two separate files. Per-file atomic writes
prevent torn secret contents, while explicit partial-state detection prevents an interrupted pair
from being accepted as complete.

**Alternatives considered**: A symlink-switched credential directory could provide set-level
atomicity but would change all existing file-path contracts and complicate Key Vault ingestion for
two small files. Direct writes were rejected because interruption could leave truncated secrets.

## Validation and evidence

**Decision**: Validate length, full allowed-character membership, per-class counts, and
cross-credential inequality before accepting new files. Emit a JSON receipt containing only
profile IDs, target/account labels, disposition (`generated` or `preserved`), validation booleans,
file-mode checks, uniqueness status, and timestamp. Do not record values, hashes, prefixes,
suffixes, character positions, or class counts derived from preserved values.

**Rationale**: The receipt proves that the gate ran without creating a password verifier or leaking
typing clues. Target/account labels remain unambiguous.

**Alternatives considered**: Password hashes were rejected because they are unnecessary
secret-derived material and enable offline guessing. Logging length/class counts for preserved
legacy values was rejected because the acceptance evidence needs only disposition and gate status.

## Integration with bootstrap and Key Vault

**Decision**: Invoke the credential-set generator in the runbook before
`generate_cyclecloud_bootstrap_secrets.sh`. Remove CycleCloud administrator password creation from
that TLS-focused script and require the file to exist. Keep the existing Key Vault secret names
`windows-admin-password` and `cyclecloud-admin-password`.

Feature 005 requires the successful credential receipt and existing Key Vault references but owns
no password generation or rotation.

**Rationale**: One generator can enforce cross-credential uniqueness before either password is
accepted. Stable file and Key Vault names avoid infrastructure, bootstrap, and migration changes.
TLS/PFX passwords are machine-only and remain outside the usability feature.

**Alternatives considered**: Independent generators were rejected because they cannot reliably
enforce pair uniqueness or all-or-review interruption behavior. Moving password generation into
Terraform was rejected because generated secrets would enter Terraform state and violate the
security boundary.
