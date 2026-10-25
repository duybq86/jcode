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

FROM alpine:3.22
RUN apk add --no-cache ca-certificates git openssh-client chromium font-noto font-noto-cjk font-noto-emoji \
    && addgroup -S jcode \
    && adduser -S -G jcode -h /home/jcode jcode \
    && mkdir -p /workspace \
    && chown jcode:jcode /workspace
COPY --from=build /out/jcode /usr/local/bin/jcode
# jcode looks up google-chrome/chromium on PATH. Wrap Alpine's chromium with the flags
# needed in a locked-down container (no user namespaces for the sandbox, small /dev/shm,
# no GPU, and crashpad needs a database dir that a read-only rootfs does not have).
RUN printf '%s\n' '#!/bin/sh' \
    'exec /usr/bin/chromium --no-sandbox --disable-dev-shm-usage --disable-gpu --disable-breakpad "$@"' \
    > /usr/local/bin/google-chrome \
    && chmod 755 /usr/local/bin/google-chrome
ENV HOME=/home/jcode
USER jcode
WORKDIR /workspace
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/jcode"]
CMD ["web", "--host", "0.0.0.0", "--port", "8080", "--open=false"]
