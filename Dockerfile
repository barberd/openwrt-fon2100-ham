FROM ubuntu:14.04
RUN apt-get update && apt-get install -y \
    build-essential libncurses5-dev gawk git subversion \
    libssl-dev gettext unzip zlib1g-dev file python wget \
    bzip2 tar patch \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /bin/tar /usr/bin/tar \
    && ln -sf /bin/bash /usr/bin/bash
RUN useradd -m builder
USER builder
WORKDIR /home/builder/openwrt
