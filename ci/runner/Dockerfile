# Self-hosted GitHub Actions runner for the K1 lab: builds K1K/K1OS/WARP,
# boots ISOs in QEMU (with KVM when the host passes /dev/kvm) and drives the
# host's Docker daemon through the mounted socket.
FROM ubuntu:24.04

ARG RUNNER_VERSION=2.337.0
ARG DOCKER_CLI_VERSION=27.5.1
ARG GH_VERSION=2.101.0

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_ALLOW_RUNASROOT=1 \
    RUSTUP_HOME=/opt/rust/rustup \
    CARGO_HOME=/opt/rust/cargo \
    PATH=/opt/rust/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl jq git rsync make build-essential pkg-config \
        xorriso mtools squashfs-tools cpio gzip xz-utils \
        qemu-system-x86 qemu-utils ovmf socat \
        libssl-dev libcurl4-openssl-dev zlib1g-dev \
        python3 \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI only — the daemon is the host's, reached via /var/run/docker.sock.
RUN curl -fsSL "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_CLI_VERSION}.tgz" \
        | tar -xz -C /usr/local/bin --strip-components=1 docker/docker

RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
        | tar -xz -C /usr/local/bin --strip-components=2 "gh_${GH_VERSION}_linux_amd64/bin/gh"

# Rust: rustup + nightly with the pieces K1K needs; repos with a
# rust-toolchain.toml still get exactly the toolchain they pin.
RUN curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal \
        --default-toolchain nightly -c rust-src -c rustfmt -c clippy -t x86_64-unknown-none \
    && chmod -R a+rwX /opt/rust

WORKDIR /runner
RUN curl -fsSL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
        | tar -xz \
    && ./bin/installdependencies.sh \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
