# Data Model: User-Friendly Generated Passwords

## Password Policy Profile

Defines the acceptance rules for one newly generated interactive credential.

| Field | Type | Rules |
|---|---|---|
| `id` | string | Stable identifier; `interactive-admin-v1` |
| `length` | integer | Exactly `16` |
| `uppercaseAlphabet` | string | `ABCDEFGHJKLMNPQRSTUVWXYZ` |
| `lowercaseAlphabet` | string | `abcdefghijkmnopqrstuvwxyz` |
| `numericAlphabet` | string | `23456789` |
| `specialAlphabet` | string | `!@#$%^*()-_+=` |
| `minimumPerClass` | integer | Exactly `2` |

All alphabets are nonempty and mutually classified. Every generated character must belong to
exactly one approved class for validation purposes.

## Generated Credential

A protected value plus non-secret identity known only in process memory and its mode-`0600` file.

| Field | Type | Rules |
|---|---|---|
| `target` | enum | `windows` or `cyclecloud` |
| `account` | string | `windowsadmin` or `hpcadmin` |
| `secretName` | string | Existing Key Vault name |
| `protectedPath` | path | Absolute path under protected run state |
| `policyProfile` | string | `interactive-admin-v1` for new generation |
| `disposition` | enum | `generated` or `preserved` |
| `value` | secret string | Process memory/protected file only; never serialized to evidence |

The target/account/secret-name tuples are:

| Target | Account | Secret name |
|---|---|---|
| Windows VM | `windowsadmin` | `windows-admin-password` |
| CycleCloud application | `hpcadmin` | `cyclecloud-admin-password` |

## Credential Set

The two administrative credentials governed as one logical unit.

| Field | Type | Rules |
|---|---|---|
| `windows` | Generated Credential | Required |
| `cyclecloud` | Generated Credential | Required |
| `uniquenessValidated` | boolean | True before a new set is accepted |
| `lockPath` | path | One exclusive lock per evidence run |
| `state` | enum | See transitions below |

## Credential-Set State

```text
absent
  -> locked
  -> generating
  -> validating
  -> writing
  -> complete_generated

complete_existing
  -> locked
  -> complete_preserved

partial_existing
  -> locked
  -> failed_partial

generating | validating
  -> failed_no_write

writing
  -> complete_generated
  -> partial_existing   (only if interrupted between atomic file replacements)
```

`complete_generated` and `complete_preserved` are terminal for ordinary repeated execution.
Rotation is outside this feature and requires a separate approved workflow.

## Validation Result

Used only while validating a newly generated value.

| Field | Type | Rules |
|---|---|---|
| `lengthValid` | boolean | Value length is exactly 16 |
| `allowedCharactersValid` | boolean | Every character is in the combined alphabet |
| `uppercaseValid` | boolean | At least two |
| `lowercaseValid` | boolean | At least two |
| `numericValid` | boolean | At least two |
| `specialValid` | boolean | At least two |

No validation result containing character positions, substrings, or a value-derived digest may be
persisted.

## Credential Evidence

The secret-free receipt consumed by storage and feature 005 gates.

| Field | Type | Rules |
|---|---|---|
| `schemaVersion` | integer | Exactly `1` |
| `status` | enum | `generated` or `preserved` |
| `policyProfile` | string | `interactive-admin-v1` |
| `targets` | array | Exactly the two target/account/secret-name records |
| `newValuePolicyValidated` | boolean | True for generated; null for preserved legacy sets |
| `uniquenessValidated` | boolean | True after in-memory comparison |
| `protectedModesValidated` | boolean | Both files are mode `0600` |
| `completedAt` | timestamp | UTC RFC 3339 |

The evidence contains no password value, hash, encoded value, prefix/suffix, or reversible
secret-derived material.
