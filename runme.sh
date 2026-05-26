#!/bin/bash
set -e
cd ~/openwrt-aa

docker build -t openwrt-aa-builder .

docker run --rm -v "$(pwd)":/home/builder/openwrt -w /home/builder/openwrt openwrt-aa-builder \
  bash -c "rm -rf build_dir/linux-atheros/compat-wireless-2014-05-22 && make -j13 V=s" 2>&1 | tee build.log
