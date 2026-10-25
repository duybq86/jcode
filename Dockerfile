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
RUN apk add --no-cache ca-certificates git openssh-client \
    && addgroup -S jcode \
    && adduser -S -G jcode -h /home/jcode jcode \
    && mkdir -p /workspace \
    && chown jcode:jcode /workspace
COPY --from=build /out/jcode /usr/local/bin/jcode
ENV HOME=/home/jcode
USER jcode
WORKDIR /workspace
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/jcode"]
CMD ["web", "--host", "0.0.0.0", "--port", "8080", "--open=false"]
