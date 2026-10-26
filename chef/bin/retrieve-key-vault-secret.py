#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid


IMDS_ENDPOINT = "http://169.254.169.254/metadata/identity/oauth2/token"
TOKEN_RESOURCE = "https://vault.azure.net"
VAULT_API_VERSION = "7.4"
SECRET_NAME = re.compile(r"^[0-9A-Za-z-]{1,127}$")
VAULT_URI = re.compile(r"^https://[a-z0-9-]+\.vault\.azure\.net/?$")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--client-id", required=True)
    parser.add_argument("--vault-uri", required=True)
    parser.add_argument("--secret-name", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=float, default=10.0)
    arguments = parser.parse_args(argv)
    try:
        uuid.UUID(arguments.client_id)
    except ValueError as error:
        raise SystemExit("invalid managed identity client ID") from error
    if not VAULT_URI.fullmatch(arguments.vault_uri):
        raise SystemExit("vault URI must be a private-DNS-routed Azure Key Vault URI")
    if not SECRET_NAME.fullmatch(arguments.secret_name):
        raise SystemExit("invalid Key Vault secret name")
    if arguments.timeout <= 0 or arguments.timeout > 30:
        raise SystemExit("timeout must be greater than zero and no more than 30 seconds")
    return arguments


def _json_request(request: urllib.request.Request, timeout: float) -> dict[str, object]:
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            document = json.loads(response.read())
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        raise RuntimeError("protected endpoint request failed") from error
    if not isinstance(document, dict):
        raise RuntimeError("protected endpoint returned an invalid document")
    return document


def _protected_write(path: Path, value: str) -> None:
    if not path.is_absolute():
        raise RuntimeError("secret output path must be absolute")
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(path.parent, 0o700)
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            output.write(value)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(path, 0o600)
    except BaseException:
        path.unlink(missing_ok=True)
        raise


def main(argv: list[str] | None = None) -> int:
    arguments = parse_args(argv)
    query = urllib.parse.urlencode(
        {
            "api-version": "2018-02-01",
            "resource": TOKEN_RESOURCE,
            "client_id": arguments.client_id,
        }
    )
    token_request = urllib.request.Request(
        f"{IMDS_ENDPOINT}?{query}",
        headers={"Metadata": "true"},
    )
    token_document = _json_request(token_request, arguments.timeout)
    token = token_document.get("access_token")
    if not isinstance(token, str) or not token:
        raise RuntimeError("managed identity token response was incomplete")

    vault_uri = arguments.vault_uri.rstrip("/")
    secret_name = urllib.parse.quote(arguments.secret_name, safe="")
    secret_request = urllib.request.Request(
        f"{vault_uri}/secrets/{secret_name}?api-version={VAULT_API_VERSION}",
        headers={"Authorization": f"Bearer {token}"},
    )
    secret_document = _json_request(secret_request, arguments.timeout)
    value = secret_document.get("value")
    if not isinstance(value, str) or not value:
        raise RuntimeError("Key Vault response did not contain a secret value")
    _protected_write(arguments.output, value)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1) from None
