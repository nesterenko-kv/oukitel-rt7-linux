FROM debian:bookworm-slim@sha256:6bd27d44e6c32a66bbd72d7cb2b76a8ae3497ec2e5274a81abd1b37f6013fa1f

ARG DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8

COPY apt/debian.sources /etc/apt/sources.list.d/debian.sources
COPY policy-rc.d /usr/sbin/policy-rc.d

RUN rm -f /etc/apt/sources.list \
    && chmod 0755 /usr/sbin/policy-rc.d \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install --yes --no-install-recommends ca-certificates \
    && sed -i 's#http://snapshot.debian.org#https://snapshot.debian.org#g' \
        /etc/apt/sources.list.d/debian.sources \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install --yes --no-install-recommends \
        bash-completion \
        curl \
        dbus \
        docker.io \
        e2fsprogs \
        iproute2 \
        iptables \
        iputils-ping \
        jq \
        kmod \
        less \
        nftables \
        openssh-server \
        procps \
        sudo \
        systemd-sysv \
        tzdata \
        udev \
        util-linux \
        vim-tiny \
    && rm -f /usr/sbin/policy-rc.d \
    && rm -rf /var/lib/apt/lists/* /var/lib/docker/* /var/log/* \
    && rm -f /etc/ssh/ssh_host_* /etc/machine-id \
    && install -m 0444 /dev/null /etc/machine-id \
    && useradd --create-home --uid 1000 --shell /bin/bash rt7 \
    && usermod --append --groups docker,sudo rt7 \
    && passwd --lock root \
    && passwd --lock rt7 \
    && install -d -m 0700 -o rt7 -g rt7 /home/rt7/.ssh \
    && install -d -m 0755 /etc/docker /etc/ssh/sshd_config.d /run/sshd \
    && systemctl enable docker.service ssh.service

COPY docker/daemon.json /etc/docker/daemon.json
COPY ssh/rt7.conf /etc/ssh/sshd_config.d/rt7.conf
COPY sudoers/rt7 /etc/sudoers.d/rt7
COPY systemd/ssh-keygen.conf /etc/systemd/system/ssh.service.d/rt7-keygen.conf
COPY bin/rt7-chroot-start /usr/local/sbin/rt7-chroot-start
COPY bin/rt7-healthcheck /usr/local/sbin/rt7-healthcheck

RUN chmod 0440 /etc/sudoers.d/rt7 \
    && chmod 0644 /etc/docker/daemon.json /etc/ssh/sshd_config.d/rt7.conf \
        /etc/systemd/system/ssh.service.d/rt7-keygen.conf \
    && chmod 0755 /usr/local/sbin/rt7-chroot-start /usr/local/sbin/rt7-healthcheck \
    && update-alternatives --set iptables /usr/sbin/iptables-legacy \
    && update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy \
    && /usr/bin/ssh-keygen -A \
    && /usr/sbin/sshd -t \
    && /usr/bin/jq -e \
        '."storage-driver" == "overlay2" and .iptables == true' \
        /etc/docker/daemon.json >/dev/null \
    && rm -f /etc/ssh/ssh_host_*

STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
