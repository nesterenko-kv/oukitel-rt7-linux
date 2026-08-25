# Kernel compile baseline

The pinned source, module tree, configuration merge, compatibility patches,
and Android clang toolchain produce a complete ARM64 Linux 4.19.191 `Image`.
No device partition was read or written to obtain this result.

## Reproduction

Run the documented preparation steps once, then build with:

```sh
docker compose run --rm kernel-builder /project/scripts/build-kernel.sh
```

The script derives `SOURCE_DATE_EPOCH` and `KBUILD_BUILD_TIMESTAMP` from the
pinned kernel commit and fixes the build user, host, and version. It writes
only final artifacts to the private sibling directory:

```text
../oukitel-rt7-linux-work/build/kernel/artifacts/
```

## Verified output

Two consecutive builds produced identical hashes:

```text
a5889c9625f7535c7eb03e9e71dcaa98b15abcdcd4e7775fc1468612b8c5dc97  Image
9373896e6bc568d96d1d8b8d52cb0d6e3dc20f849693000f87f2e0982e00a269  Image.gz
b72a84547c2c574355ace53874674cc07b9085fb096f31cdab9b82619ffa625a  System.map
a7dd8b8059ec08fa309acba3a6ff2ad82dcdf38aa586fc03cb24b3ed3f730732  kernel.config
```

The raw image is 29,151,232 bytes and the reproducible gzip is 12,227,678
bytes. The official V1.4.8 reference kernel is 29,730,816 bytes raw and
12,725,131 bytes compressed, so the local kernel component is smaller in both
forms. The result identifies as a little-endian AArch64 Linux boot image with
4 KiB pages. Its embedded compiler is Android clang 11.0.1 `r383902`.

Validation includes `sha256sum -c`, gzip integrity and round-trip comparison,
ARM64 image identification, and inspection of the AArch64 `vmlinux` ELF header.

## Safety boundary

This output is not yet a boot image or a release candidate. In particular:

- it does not contain the stock ramdisk, DTB/DTBO, boot header, or AVB data;
- the exact OUKITEL board source and most configured RT7 camera drivers remain
  unavailable;
- OPPO implementation configs were merged to satisfy assumptions in the
  public source and have not been audited against RT7 hardware;
- no exact-installed-build rollback image or tested bootloader recovery route
  exists yet.

Do not pack or flash this artifact until those gaps and the recovery checklist
in `docs/boot-chain.md` are resolved.
