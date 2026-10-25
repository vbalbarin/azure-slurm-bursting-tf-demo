# CycleCloud 8.9.3 User UI Gate Contract

## Supported boundary

CycleCloud 8.9.3 documents application-user creation, node-access configuration, and per-cluster
sharing only through the web UI. Its CLI `account` commands manage cloud-provider accounts, and
its published REST API has no application-user resource. This gate MUST NOT call or infer an
undocumented datastore, private endpoint, or payload.

## Preconditions

- CycleCloud convergence evidence is accepted and exactly one stopped `cross-region-demo` cluster
  exists.
- Scheduler convergence evidence and a public-identity receipt for `hpcuser01` are accepted.
- The receipt contains UID/GID `11200`, home `/shared/home/hpcuser01`, one Ed25519 public key, its
  SHA-256 fingerprint, approved source/specification digests, and a canonical receipt digest.
- The operator authenticates through the protected `hpcadmin` path.

## Required UI outcome

In **Settings > Users**, create or edit `hpcuser01` so that:

- Superuser is disabled.
- Node access is enabled.
- Unix UID is `11200`.
- The SSH public key exactly matches the scheduler receipt.

In the `cross-region-demo` **Access** dialog, grant `hpcuser01` non-administrative node-user access
to that cluster only. Do not grant Administrator, Global Node Admin, or global cluster privileges.

If user creation requires an interactive password, generate a one-time value with a
cryptographically secure password generator inside the protected operator session. It MUST satisfy
the accepted feature 004 CycleCloud password policy, be entered only in the UI, require password
reset, and be discarded immediately after submission. It MUST NOT enter run state, command
history, clipboard history, logs, screenshots, or evidence. Password login for `hpcuser01` is
outside acceptance.

## Attestation

Record a schema-version `1` attestation containing only:

- Accountable operator identifier and UTC completion time.
- User name `hpcuser01`.
- `superuser: false`, `nodeAccessEnabled: true`, and UID `11200`.
- Scheduler public-key fingerprint.
- Scheduler source revision, specification digest, and identity-receipt digest.
- Cluster name `cross-region-demo` and permission `node-user`.
- Application-password disposition `not-required` or `force-reset-discarded`.
- Result `accepted` or `rejected`.

The attestation MUST NOT contain a password, session token, complete public key, private key,
protected screenshot, or undocumented CycleCloud record.

## Verification and failure behavior

- The governed workflow validates the attestation's source revision, specification digest,
  identity-receipt digest, and public-key fingerprint against the current scheduler receipt before
  allowing burst-node creation. Any mismatch is stale.
- The first burst node MUST show user `hpcuser01`, UID `11200`, successful key-based access through
  the accepted path, and correct shared-home ownership. Evidence MUST record the observed primary
  GID and reject any identity or ownership conflict; the UI contract does not claim to configure
  that GID.
- CycleCloud's cluster Users status MUST show no UID conflict or disallowed-name warning.
- A missing, malformed, rejected, stale, overprivileged, or fingerprint-mismatched attestation
  blocks burst-node creation.
- A compute-node UID, key, access, identity/ownership, or shared-home mismatch fails acceptance and
  requires UI correction or clean node replacement; automation MUST NOT patch CycleCloud's
  internal datastore.
