# Boot-image dry run

This milestone validates boot-image construction offline. It does not unlock,
boot, flash, or otherwise write to the tablet.

## Pinned tooling

The project uses `mkbootimg.py`, `unpack_bootimg.py`, and `avbtool.py` from the
annotated AOSP `android-13.0.0_r1` tag. Both the tag objects and peeled commits
are recorded in `sources.lock`.

## Stock round trip

The official V1.4.8 `boot.img` is a 41,943,040-byte AVB image. Its signed boot
payload is 25,131,008 bytes; the remainder contains padding, VBMeta, and the AVB
footer. Rebuilding the payload from the unpacked header-v2 arguments, stock
kernel, ramdisk, and DTB produced all 25,131,008 bytes identically.

This byte-for-byte comparison is a mandatory gate in
`scripts/build-test-boot-image.py`. The script refuses to create a custom
artifact if the stock payload cannot be reproduced exactly.

## Kernel-only substitution

The script then replaces only the compressed kernel with the reproducible
local `Image.gz`. It unpacks the result again and verifies that:

- the custom kernel round-trips byte-for-byte;
- the stock ramdisk and DTB remain byte-identical;
- every boot header argument remains unchanged;
- the custom payload does not exceed the original payload size;
- no output is written inside the public repository.

The current private test artifact is:

```text
filename: rt7-v148-kernel-unsigned-do-not-flash.img
size:     24,633,344 bytes
sha256:   edcb547a0465d19f01df5157be61a9650059fd276544dfd1fe52c2adc4b6d2c1
```

It is deliberately unsigned and has no AVB footer. Its filename and JSON
manifest both state `do-not-flash`. A valid Android boot image container is not
the same thing as a bootable or safe image.

## Remaining gate

Before a boot attempt, the project still needs an exact rollback path, a
verified unlock/recovery procedure, and a decision between nonpersistent
`fastboot boot` and a controlled inactive-slot test. No AVB bypass or test-key
signing will be added merely to make the image flashable.
