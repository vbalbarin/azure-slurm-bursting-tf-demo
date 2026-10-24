# Phase 0 Research: Automated Chef Bootstrap and Convergence

## Policy delivery

**Decision**: Build one deterministic, role-specific compressed policy bundle from source and
deliver it with its manifest and node specification through Azure VM custom data. The bundle is
non-secret, is SHA-256 verified before extraction, and is atomically staged under
`/opt/slurm-demo/releases/<digest>`. Fail the build if the decoded cloud-init document exceeds
60,000 bytes, preserving margin below Azure's 65,535-byte custom-data limit.

**Rationale**: The current combined role content compresses to approximately 19 KB and Base64
encodes to approximately 25 KB. Direct delivery therefore avoids a new storage account, private
endpoint, DNS zone, uploader path, and RBAC lifecycle. Custom data already crosses the protected
Azure control plane and contains no secret values.

**Alternatives considered**: A dedicated private artifact storage account was rejected because the
governed runner has no private data-plane route with public access disabled, creating a separate
population bootstrap problem. The Terraform state container was rejected as a workload artifact
channel. Individual file embedding was rejected because a deterministic archive and manifest are
easier to validate and switch atomically.

## Configuration client

**Decision**: Install Chef Infra Client `18.11.11` for EL9 from its immutable vendor URL and verify
SHA-256 `d68c339bc85ded67b793de4e20f35886c5fbd9b5a9e95dabbe5ede6211b01365`
before `rpm` installation. Record license acceptance with `accept-no-persist`. Reuse the installed
version only when it exactly matches the manifest.

**Rationale**: The omnibus RPM is too large for custom data. The official metadata endpoint
provides an exact URL, version, platform, and digest. Exact verification satisfies reproducibility
without introducing package-repository drift.

**Alternatives considered**: Installing unpinned `latest` was rejected. Bundling the RPM in custom
data exceeds the platform limit. Chef Server and the Chef VM extension were rejected because this
feature uses local mode and has no Chef Server.

## CycleCloud Slurm release inputs

**Decision**: Pin CycleCloud Slurm `4.0.11`. Use
`azure-slurm-pkg-4.0.11.tar.gz` with SHA-256
`f85a1d016eca3786eb9845fcbffcefaf674bfcd4b59738597e90877047a23e36`
for the CycleCloud project and `azure-slurm-install-pkg-4.0.11.tar.gz` with SHA-256
`a489f4c5ec2404dc02a09792af5f32f4683e164327d89c4c2dfc8d9a30402482`
for the external scheduler. Download only the exact release URLs and verify before extraction.
Use the repository's tested headless transformer to create a separate validated external-scheduler
template; never edit the vendor template in place.

**Rationale**: The release publishes distinct, digest-identified project and external-scheduler
artifacts. One release identity across both roles prevents package/template skew.

**Alternatives considered**: Discovering an arbitrary installed project was rejected because a new
Marketplace appliance does not guarantee the required external-scheduler artifact. Tracking the
repository default branch was rejected as mutable. A private fork was rejected because the
official release already exposes the required installation package.

## Scheduler secret retrieval and integration credential

**Decision**: Grant only the scheduler user-assigned identity `Key Vault Secrets User` on the
existing vault. Retrieve `cyclecloud-admin-password` at runtime through IMDS and the Key Vault REST
API over the existing private endpoint. Keep the value only in a root-owned temporary file or
process variable and remove it through an unconditional trap.

Invoke the release-matched `azslurm initconfig` once as root with shell tracing disabled, restrictive
umask, and process visibility limited to privileged users. Install its output at mode `0600`, then
unset/remove all temporary credential material.

**Rationale**: Key Vault REST avoids installing Azure CLI on the scheduler and preserves managed
identity authentication. Source inspection confirms that the vendor integration requires
`--password` and offers no password-file, stdin, or environment alternative; the restricted
transient argument is therefore an explicit product-boundary exception rather than an unsupported
hand-written credential format.

**Alternatives considered**: A custom long-lived credential file was rejected because its schema
is not the supported integration entry point. Patching `azslurm` was rejected as an unmaintained
fork. Giving the scheduler secret-write access was rejected as unnecessary.

## `hpcuser01` identity and key reconciliation

**Decision**: Use UID/GID `11200`. Chef creates the scheduler group and user through supported
resources with home `/shared/home/hpcuser01`, then generates an Ed25519 key once when absent. The
private key remains mode `0600` in the shared home. The governed workflow reads only the public
key through Azure VM Run Command and invokes a root-only CycleCloud reconciliation helper.

The helper uses the version-qualified CycleCloud 8.9.3 application import interface to idempotently
create or update the non-superuser application record, UID/GID metadata, public key, and
`cross-region-demo` cluster access. It verifies the resulting record before emitting a secret-free
receipt. Burst-node creation remains blocked until that receipt matches the scheduler key
fingerprint and UID/GID.

**Rationale**: This preserves the original demonstration model: the scheduler is the key-pair
authority, CycleCloud propagates the public identity to burst nodes, and the same numeric identity
owns the shared home. A fixed value avoids nondeterministic UI-assigned UIDs.

**Alternatives considered**: Directly editing Linux account databases was rejected. Creating a
local `hpcuser01` on the appliance was rejected because it confuses OS and CycleCloud application
identities. Pre-generating a second private key outside the scheduler was rejected because it
unnecessarily broadens private-key custody. LDAP/AD remains a documented production extension,
not part of this bounded demo.

## Dependency dispatch

**Decision**: Use the governed end-to-end workflow and Azure VM Run Command. It verifies the
CycleCloud state receipt, imported cluster, scheduler environment-ready receipt, Key Vault RBAC,
and required secret references; invokes the scheduler wrapper; reconciles `hpcuser01`; and then
performs second-run checks. All Run Command payloads contain references or public data, never
secrets.

**Rationale**: Run Command works without public ingress and uses the existing Azure authorization
boundary. The operator workflow already owns ordered, evidence-producing deployment actions.

**Alternatives considered**: Scheduler cloud-init polling was rejected as unbounded and racy. A
timer or daemon was rejected because existing VMs must not silently apply policy changes. SSH from
the external runner was rejected because the accepted access path is through Bastion/Windows.

## State, retry, and evidence

**Decision**: Serialize each role with `flock`. Write atomic JSON state and evidence records under
`/var/lib/slurm-demo`, keyed by role and approved input digests. Permit attempts 1 and 2 only when
all approved digests are identical. After a second failure, write `replacement_required` and
refuse further convergence. A successful run allows explicit idempotency verification but resets
no failure history.

**Rationale**: Explicit attempt identity prevents a changed input from being mislabeled a retry
and prevents manual repair from becoming clean-boot evidence. Atomic records remain inspectable
after interruption.

**Alternatives considered**: Unlimited retries and automatic backoff were rejected because they
hide deterministic failures. Marker-only text files were rejected because they cannot bind state
to source and artifact identity.
