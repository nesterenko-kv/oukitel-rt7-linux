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
```
