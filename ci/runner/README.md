# K1 lab runners

Self-hosted GitHub Actions runners for `KEYTRON/K1K`, `KEYTRON/K1OS` and
`KEYTRON/WARP`, one container each, running on the lab machine. They exist
because GitHub's hosted runners cannot boot our OS (no KVM, no prebuilt
rootfs) and because every job on them burns account minutes.

```sh
ci/runner/up.sh            # build image, fetch registration tokens via gh, start all
docker compose -f ci/runner/docker-compose.yml logs -f runner-k1k
docker compose -f ci/runner/docker-compose.yml down   # stop (runners stay registered)
```

What a runner sees:

| Mount / device | Purpose |
|----------------|---------|
| `/var/run/docker.sock` | build and run containers on the host daemon (K1OS image, WARP distro matrix) |
| `/dev/kvm` | fast QEMU for kernel boot tests |
| `/lab/git` (read-only) | the lab checkouts; K1OS builds the private K1K kernel from `/lab/git/K1K` |
| `/runner` (volume) | runner config, credentials and `_work` — persists between restarts |

The containers use the host network: the lab host bypasses DPI blocking of
`*.githubusercontent.com` with zapret, and only host-networked traffic gets
that treatment (bridge-networked `docker build`s time out on GitHub release
downloads — pass `--network=host` to `docker build` in jobs that need them).

Workflows target them with `runs-on: [self-hosted, k1lab]` (plus `k1k`,
`k1os` or `warp` if a job must land on a specific repo's runner). The image
ships Rust nightly (`rustup`, `x86_64-unknown-none`, `rust-src`), QEMU + OVMF,
xorriso, mtools, squashfs-tools, the Docker CLI and `gh`.
