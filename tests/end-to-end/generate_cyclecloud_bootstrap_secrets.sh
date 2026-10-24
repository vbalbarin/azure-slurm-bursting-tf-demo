#!/usr/bin/env bash
set -euo pipefail
umask 077

for command in openssl; do
  command -v "$command" >/dev/null || {
    printf 'Missing required command: %s\n' "$command" >&2
    exit 2
  }
done

: "${CYCLECLOUD_PRIVATE_NAME:?CYCLECLOUD_PRIVATE_NAME is required}"
: "${CYCLECLOUD_ADMIN_PASSWORD_FILE:?CYCLECLOUD_ADMIN_PASSWORD_FILE is required}"
: "${CYCLECLOUD_TLS_PFX_FILE:?CYCLECLOUD_TLS_PFX_FILE is required}"
: "${CYCLECLOUD_TLS_PFX_PASSWORD_FILE:?CYCLECLOUD_TLS_PFX_PASSWORD_FILE is required}"
: "${CYCLECLOUD_TLS_CA_FILE:?CYCLECLOUD_TLS_CA_FILE is required}"

[[ -f "$CYCLECLOUD_ADMIN_PASSWORD_FILE" ]] || {
  printf 'Pre-generated CycleCloud administrator password does not exist\n' >&2
  exit 2
}
[[ "$(stat -c '%a' "$CYCLECLOUD_ADMIN_PASSWORD_FILE")" == "600" ]] || {
  printf 'CycleCloud administrator password must have mode 0600\n' >&2
  exit 2
}

if [[ ! -f "$CYCLECLOUD_TLS_PFX_PASSWORD_FILE" ]]; then
  printf 'Aa1!%s' "$(openssl rand -base64 36 | tr -d '\r\n')" \
    >"$CYCLECLOUD_TLS_PFX_PASSWORD_FILE"
fi

if [[ ! -f "$CYCLECLOUD_TLS_PFX_FILE" || ! -f "$CYCLECLOUD_TLS_CA_FILE" ]]; then
  work_dir="$(mktemp -d)"
  cleanup() {
    rm -rf "$work_dir"
  }
  trap cleanup EXIT

  openssl req -x509 -newkey rsa:4096 -sha256 -days 825 -nodes \
    -subj "/CN=${CYCLECLOUD_PRIVATE_NAME} Demo Root CA" \
    -keyout "$work_dir/ca.key" \
    -out "$work_dir/ca.crt"
  openssl req -newkey rsa:4096 -nodes -sha256 \
    -subj "/CN=${CYCLECLOUD_PRIVATE_NAME}" \
    -keyout "$work_dir/server.key" \
    -out "$work_dir/server.csr"
  cat >"$work_dir/server.ext" <<EOF
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:${CYCLECLOUD_PRIVATE_NAME}
EOF
  openssl x509 -req -sha256 -days 825 \
    -in "$work_dir/server.csr" \
    -CA "$work_dir/ca.crt" \
    -CAkey "$work_dir/ca.key" \
    -CAcreateserial \
    -extfile "$work_dir/server.ext" \
    -out "$work_dir/server.crt"
  openssl pkcs12 -export \
    -name identity \
    -inkey "$work_dir/server.key" \
    -in "$work_dir/server.crt" \
    -certfile "$work_dir/ca.crt" \
    -passout "file:$CYCLECLOUD_TLS_PFX_PASSWORD_FILE" \
    -out "$CYCLECLOUD_TLS_PFX_FILE"
  install -m 0600 "$work_dir/ca.crt" "$CYCLECLOUD_TLS_CA_FILE"
fi

chmod 0600 \
  "$CYCLECLOUD_ADMIN_PASSWORD_FILE" \
  "$CYCLECLOUD_TLS_PFX_FILE" \
  "$CYCLECLOUD_TLS_PFX_PASSWORD_FILE" \
  "$CYCLECLOUD_TLS_CA_FILE"

openssl pkcs12 -in "$CYCLECLOUD_TLS_PFX_FILE" -noout \
  -passin "file:$CYCLECLOUD_TLS_PFX_PASSWORD_FILE"
openssl x509 -in "$CYCLECLOUD_TLS_CA_FILE" -noout -checkend 86400
