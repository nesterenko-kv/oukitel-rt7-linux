FROM ubuntu:24.04@sha256:33ceb71981b602c1a7443a53469e4dba065f7503eab3078a2d7a57a2ab987517

ARG DEBIAN_FRONTEND=noninteractive
ARG MTKCLIENT_COMMIT=4d29037104b1f378abedcace89ccd48e8a8aa314

RUN apt-get update \
    && apt-get install --yes --no-install-recommends \
        ca-certificates \
        git \
        libusb-1.0-0 \
        python3 \
        python3-pip \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN git init /opt/mtkclient \
    && git -C /opt/mtkclient remote add origin https://github.com/bkerler/mtkclient.git \
    && git -C /opt/mtkclient fetch --depth 1 origin "${MTKCLIENT_COMMIT}" \
    && git -C /opt/mtkclient checkout --detach FETCH_HEAD \
    && test "$(git -C /opt/mtkclient rev-parse HEAD)" = "${MTKCLIENT_COMMIT}"

COPY requirements.txt /tmp/mtkclient-requirements.txt

WORKDIR /opt/mtkclient

RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir --requirement /tmp/mtkclient-requirements.txt \
    && /opt/venv/bin/python -c \
       'from mtkclient.config.brom_config import hwconfig; assert hwconfig[0x996].dacode == 0x6853' \
       </dev/null

ENTRYPOINT ["/opt/venv/bin/python", "/opt/mtkclient/mtk.py"]
CMD ["--help"]
