FROM mcr.microsoft.com/devcontainers/python:1-3.12-bookworm

COPY --from=ghcr.io/astral-sh/uv:0.12.23 /uv /uvx /usr/local/bin/

RUN rm -f /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      dnsutils \
      git \
      jq \
      libarchive-dev \
      libffi-dev \
      libssl-dev \
      make \
      netcat-openbsd \
      openssh-client \
      shellcheck \
      unzip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -o vscode -g vscode -m 0700 /evidence
