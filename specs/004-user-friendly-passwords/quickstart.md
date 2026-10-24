# Quickstart: Validate User-Friendly Passwords

This guide validates feature 004 before the protected credential set is consumed by feature 005.
Do not use real accepted-environment credentials in negative tests.

## 1. Run source validation

```bash
make end-to-end-unit policy-test
```

Expected:

- Generator unit and subprocess-contract tests pass.
- JSON policy and evidence fixtures validate.
- Secret-hygiene policy tests find no password values or derived verifiers.

## 2. Generate a new protected set

Create an empty temporary directory with mode `0700` outside evidence, then run:

```bash
python3 tests/end-to-end/generate_admin_passwords.py \
  --windows-password-file "$DEMO_STATE_DIR/windows-admin-password" \
  --cyclecloud-password-file "$DEMO_STATE_DIR/cyclecloud-admin-password" \
  --evidence-file "$DEMO_STATE_DIR/admin-password-evidence.json" \
  --lock-file "$DEMO_STATE_DIR/admin-passwords.lock"
```

Expected:

- Both password files exist at mode `0600`.
- Each value is exactly 16 characters.
- Each contains at least two approved uppercase, lowercase, numeric, and special characters.
- Only characters from the profile contract appear.
- Values are different.
- No value appears on stdout, stderr, shell history, or in the evidence receipt.
- The evidence status is `generated`.

Inspect values only through the existing protected operator procedure; do not print them into
ordinary terminal capture or evidence.

## 3. Verify no-change repeat behavior

Record protected file metadata without recording content, rerun the same command, and compare
inode/content checks inside the protected context.

Expected:

- Both files are byte-for-byte unchanged.
- Neither modification time changes.
- Evidence status is `preserved`.
- No credential is rotated.

## 4. Verify partial-state failure

In an isolated fixture directory, create only one mode-`0600` credential file and run the
generator.

Expected:

- Exit code is `3`.
- The existing file is unchanged.
- The missing credential is not created.
- No success evidence is written.
- Error output contains `partial_credential_set` but no protected value.

## 5. Verify policy and uniqueness failures

Run unit fixtures that force:

- An unapproved character.
- Fewer than two characters from a class.
- Incorrect length.
- Equal Windows and CycleCloud values.
- A symlink or unsafe file mode.
- Interruption before the second atomic replacement.

Expected: every fixture fails closed, emits no protected data, and does not overwrite a previously
accepted credential.

## 6. Store through the existing Key Vault lifecycle

Continue with `tests/end-to-end/generate_cyclecloud_bootstrap_secrets.sh`, then the existing
bounded Key Vault provisioning/write/hardening sequence.

Expected:

- Secret names remain `windows-admin-password` and `cyclecloud-admin-password`.
- Storage evidence contains only Key Vault references.
- Feature 005 dependency checks accept the credential receipt and secret references.

## 7. Validate target logins

For a new evidence run:

1. Use the Windows password to authenticate as `windowsadmin` through the accepted Bastion path.
2. Use the CycleCloud password to authenticate as `hpcadmin` at the private application endpoint.

Expected: both values work without normalization or reset, and each can be typed accurately within
60 seconds. Record only pass/fail and target/account labels in secret-free evidence.

## Implementation validation record

On 2026-10-23, source validation completed without exposing protected values:

- Generator, CycleCloud stack, and secret-hygiene focus: 34 tests passed.
- Registered end-to-end unit target: 71 tests passed.
- Registered policy target: 26 tests passed.
- Local empty-set generation returned `generated`; unchanged rerun returned `preserved`.
- Full `make validate` completed successfully.

Protected `windowsadmin` and `hpcadmin` login acceptance remains bound to the next new governed
evidence run. Existing deployed credentials are not rotated to manufacture this evidence.
