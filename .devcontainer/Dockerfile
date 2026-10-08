FROM mcr.microsoft.com/devcontainers/python:1-3.12-bookworm

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
    && rm -rf /var/lib/apt/lists/*
