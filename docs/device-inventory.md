# Collecting a device inventory

`scripts/collect-device-info.sh` collects an allowlisted, read-only inventory
from a running Android system. It does not read partition contents and omits
serial numbers, IMEI data, MAC/IP addresses, accounts, and ADB credentials.

Run it through an already-authorized ADB connection and save the result outside
the public repository. Example with a local `adb` executable:

```sh
adb -s DEVICE_SERIAL shell sh < scripts/collect-device-info.sh \
  > ../oukitel-rt7-linux-work/device-dumps/device-info.txt
```

Review and sanitize any captured output before copying selected facts into the
public documentation. Device dumps themselves must not be committed.

The complete stock kernel configuration can be captured separately:

```sh
adb -s DEVICE_SERIAL exec-out cat /proc/config.gz \
  > ../oukitel-rt7-linux-work/device-dumps/stock-config.gz
```

Do not use shell text processing between `adb exec-out` and the destination
when copying compressed or binary data.
