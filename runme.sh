#!/bin/bash
set -e
cd "$(dirname "$(readlink -f "$0")")"

docker build -t openwrt-aa-builder .

docker run --rm -v "$(pwd)":/home/builder/openwrt -w /home/builder/openwrt openwrt-aa-builder \
  bash -c "./scripts/feeds update luci && ./scripts/feeds install -a && make defconfig && rm -rf build_dir/linux-atheros/compat-wireless-2014-05-22 && make -j$(nproc) V=s" 2>&1 | tee build.log
