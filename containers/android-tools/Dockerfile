FROM ubuntu:24.04@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517 AS extract

ADD --checksum=sha256:f2eee6e8220f3dfde6e1acc93c5b25d3d8bd215c0b03585b21665f1ea30d66ba \
    https://dl.google.com/android/repository/platform-tools_r34.0.4-linux.zip \
    /tmp/platform-tools.zip

RUN apt-get update \
    && apt-get install --yes --no-install-recommends unzip \
    && unzip -q /tmp/platform-tools.zip -d /opt \
    && test -x /opt/platform-tools/adb \
    && test -x /opt/platform-tools/fastboot

FROM ubuntu:24.04@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517

COPY --from=extract /opt/platform-tools /opt/android-platform-tools

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        adb=1:34.0.4-1build3 \
        android-libbase=1:34.0.4-1build3 \
        android-libboringssl=14.0.0+r11-4build1 \
        android-libcutils=1:34.0.4-1build3 \
        android-liblog=1:34.0.4-1build3 \
        android-libsparse=1:34.0.4-1build3 \
        android-libziparchive=1:34.0.4-1build3 \
        fastboot=1:34.0.4-1build3 \
        libbrotli1=1.1.0-2build2 \
        libbsd0=0.12.1-1build1.1 \
        libprotobuf32t64=3.21.12-8.2ubuntu0.3 \
        libusb-1.0-0=2:1.0.27-1 \
    && rm -rf /var/lib/apt/lists/*

# Google's libusb backend returns EIO for this MediaTek interface forwarded by
# usbipd-win. Ubuntu's 34.0.4 usbfs build works for both ADB and fastboot. Keep
# the checksum-pinned Google release available for offline comparison, but put
# the proven usbfs clients first on PATH.
ENV PATH="/usr/lib/android-sdk/platform-tools:/opt/android-platform-tools:${PATH}"

RUN adb version | grep -q 'Version 34.0.4-debian' \
    && fastboot --version | grep -q 'version 34.0.4-debian' \
    && /opt/android-platform-tools/adb version | grep -q 'Version 34.0.4-10411341' \
    && /opt/android-platform-tools/fastboot --version | grep -q 'version 34.0.4-10411341'

CMD ["sh", "-lc", "adb start-server && exec sleep infinity"]
