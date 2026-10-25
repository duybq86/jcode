FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS build

ARG TARGETOS
ARG TARGETARCH
ARG VERSION=dev
ARG COMMIT=unknown

WORKDIR /src
COPY . .

RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build \
    -trimpath -ldflags="-s -w -X github.com/cnjack/jcode/internal/command.Version=${VERSION} -X github.com/cnjack/jcode/internal/command.GitCommit=${COMMIT}" \
    -o /out/jcode ./cmd/jcode

FROM ubuntu:26.04
ENV DEBIAN_FRONTEND=noninteractive

# Base tools. Ubuntu ships a default "ubuntu" user on uid 1000, which the k8s
# manifests rely on for jcode, so remove it first. jcode gets passwordless sudo so
# the agent can apt-get install more tools (the pod must allow privilege escalation).
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg git openssh-client jq unzip zip \
        ripgrep procps less tzdata sudo bash-completion \
    && userdel -r ubuntu \
    && groupadd --system --gid 1000 jcode \
    && useradd --system --uid 1000 --gid jcode --create-home --home-dir /home/jcode --shell /bin/bash jcode \
    && echo 'jcode ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/jcode \
    && chmod 0440 /etc/sudoers.d/jcode \
    && mkdir -p /workspace \
    && chown jcode:jcode /workspace \
    && rm -rf /var/lib/apt/lists/*

# Browser for the jcode browser tool. Ubuntu's own chromium package is a snap stub
# that cannot run in a container, so use Google's official apt repo (amd64 + arm64).
RUN install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-chrome-stable fonts-liberation fonts-noto-cjk fonts-noto-color-emoji \
    && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/google-chrome.list

# jcode finds google-chrome on PATH; /usr/local/bin comes before /usr/bin. The wrapper adds
# the flags a locked-down container needs: no user namespaces for the sandbox, small /dev/shm,
# no GPU, and no crashpad (it needs a database dir that a read-only rootfs lacks).
RUN printf '%s\n' '#!/bin/sh' \
    'exec /opt/google/chrome/chrome --no-sandbox --disable-dev-shm-usage --disable-gpu --disable-breakpad "$@"' \
    > /usr/local/bin/google-chrome \
    && chmod 755 /usr/local/bin/google-chrome

COPY --from=build /out/jcode /usr/local/bin/jcode
ENV HOME=/home/jcode
USER jcode
WORKDIR /workspace
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/jcode"]
CMD ["web", "--host", "0.0.0.0", "--port", "8080", "--open=false"]
