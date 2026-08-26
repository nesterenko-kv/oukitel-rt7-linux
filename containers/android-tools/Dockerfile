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

ENV PATH="/opt/android-platform-tools:${PATH}"

RUN adb version | grep -q 'Version 34.0.4-10411341' \
    && fastboot --version | grep -q 'version 34.0.4-10411341'

CMD ["sh", "-lc", "adb start-server && exec sleep infinity"]
