# Backend Bootstrap Input Contract

The implementation must expose the following protected environment input contract. Inputs are
non-secret unless an organization classifies resource identifiers as protected metadata.

| Input | Type | Required | Validation |
|---|---|---:|---|
| `subscription_id` | UUID string | yes | Active approved subscription |
| `tenant_id` | UUID string | yes | Active approved tenant |
| `location` | region string | yes | Present in the approved region-code map |
| `workload_name` | string | yes | Lowercase alphanumeric token; generated names must fit |
| `environment_name` | string | yes | Lowercase alphanumeric or hyphen; valid Blob key prefix |
| `instance` | number | yes | Integer 0–99 |
| `uniqueness_code` | string | yes | Four to six lowercase alphanumeric characters |
| `ownership_mode` | enum | no | `managed` (default) or `existing` |
| `network_mode` | enum | no | `restricted_public` (default) or `private` |
| `operator_group_object_id` | UUID string | managed | Existing Entra security-group object ID |
| `workload_identity_object_id` | UUID string or null | no | Existing service-principal object ID |
| `allowed_public_ipv4_cidrs` | set of CIDRs | restricted-public | Non-empty public IPv4 CIDRs; no RFC1918 or catch-all |
| `private_endpoint_subnet_id` | Azure resource ID | private managed | Existing reachable subnet |
| `private_dns_zone_id` | Azure resource ID | private managed | Existing `privatelink.blob.core.windows.net` zone |
| `existing_backend` | object or null | existing | Approved resource group, account, container, resource IDs, and network mode |
| `readiness_identity` | object | yes | Active tenant plus User or ServicePrincipal object ID used for readiness |
| `tags` | string map | yes | Required governance tags; no secret-shaped keys or values |

## Cross-field rules

1. `managed` mode rejects `existing_backend`.
2. `existing` mode requires `existing_backend` and creates no Azure resources or role assignments.
3. Restricted-public mode requires explicit approved public IPv4 CIDRs and rejects `0.0.0.0/0`.
4. Private mode rejects public CIDRs and requires existing private network/DNS inputs in managed
   mode or equivalent approved coordinates in existing mode.
5. Storage naming must remain deterministic and fit Azure's 24-character account limit.
6. Operator-group and workload-identity IDs must never be tenant, application, or subscription IDs.
7. State keys are derived, not freely supplied, and must be pairwise distinct.

## Restricted-public source address

For restricted-public mode, an operator may discover the actual runner's current public IPv4
address with:

```bash
PUBLIC_IPV4="$(
  curl --ipv4 --fail --silent --show-error https://api.ipify.org
)"
printf '%s/32\n' "$PUBLIC_IPV4"
```

Use the resulting `/32` CIDR in `allowed_public_ipv4_cidrs`. Run the command from the same
runner/network context that will access the backend and after connecting any required VPN or
proxy. A changed egress address invalidates the associated readiness assessment.

`api.ipify.org` is an external service that observes the request's source address. Use it only
when organizational policy permits; otherwise obtain the egress IPv4 address through the approved
network-administration path. Do not send tokens, credentials, hostnames, usernames, or query
parameters to the echo service.

## Readiness identity

`readiness_identity` binds canonical readiness evidence to the active Entra user or service
principal that performs the readiness checks. It does not create an identity or grant access.

For an interactive Azure CLI login:

```bash
az account show --query tenantId --output tsv
az ad signed-in-user show --query id --output tsv
```

Use the first result as `readiness_identity.tenant_id`, the second as
`readiness_identity.principal_id`, and set `principal_type = "User"`.

For a service-principal login, resolve the application ID reported by the account context to the
service principal's Entra object ID:

```bash
READINESS_CLIENT_ID="$(az account show --query user.name --output tsv)"
az ad sp show --id "$READINESS_CLIENT_ID" --query id --output tsv
```

Use the lookup result as `principal_id` and set `principal_type = "ServicePrincipal"`. The
application/client ID itself is not the principal object ID. The operator-group, tenant, and
subscription IDs are also invalid substitutions.

## Readiness assertion input

After backend creation, the bootstrap root accepts a protected `readiness_assertions` object
matching `backend-readiness-assertions.schema.json`. Operators populate it from the exact
documented Azure CLI, DNS, HTTP, Terraform state, no-change-plan, and lock-conflict commands; no
custom Bash/Python helper may create or classify the assertions.

- Preliminary readiness permits `migration` and `locking` to be `not_run`.
- Final readiness requires every assertion to be `passed`.
- Any failed or inconclusive assertion produces the corresponding stable failure class.
- Every observation carries its stable command ID, UTC observation time, exit code, status,
  bounded non-secret observed value, and optional classification detail.
- A `not_run` observation uses a null exit code and empty observed value; `passed` and `failed`
  observations require an integer exit code and non-empty observed value.
- The assertion document carries the source commit, canonical coordinate digest, assessment start
  and completion times, and non-secret execution context used by native Terraform classification.
- Restricted-public context requires the observed public source IPv4 address. Private context
  requires a digest of approved private-network context. Both require resolved Blob IPv4 addresses,
  observation time, and a canonical runner-context digest.
- Changing identity, coordinates, source, execution context, or an assertion invalidates the
  previous readiness output and digest.
- Raw command output, hostnames, usernames, access tokens, and credentials are prohibited.

## Protected files

Tracked source contains only an example file. The real input file:

- is ignored by Git;
- has mode `0600`;
- is never copied into `/evidence`;
- contains no storage key, SAS token, access token, password, or certificate material.
