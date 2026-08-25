# Tooling

Host-side scripts must default to read-only inspection. Any command capable of
flashing, erasing, or unlocking a device must require an explicit target and a
separate confirmation.

The kernel preparation and configuration scripts run inside the reproducible
builder container from the repository root:

```sh
docker compose build kernel-builder
docker compose run --rm kernel-builder /project/scripts/prepare-kernel-source.sh
docker compose run --rm kernel-builder /project/scripts/merge-kernel-config.sh
docker compose run --rm kernel-builder /project/scripts/fetch-moby-check-config.sh
docker compose run --rm kernel-builder /project/scripts/audit-kernel-config.sh
docker compose run --rm kernel-builder /project/scripts/prepare-toolchain.sh
docker compose run --rm kernel-builder /project/scripts/apply-kernel-patches.sh
docker compose run --rm kernel-builder /project/scripts/build-kernel.sh
```

The build script fixes kernel build identity and timestamp inputs for
reproducibility. `Image`, `Image.gz`, `System.map`, the resolved
`kernel.config`, and `SHA256SUMS` are written under
`../oukitel-rt7-linux-work/build/kernel/artifacts/`, never to the public tree.
