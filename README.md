OpenWrt Attitude Adjustment - FON2100A Ham Radio Build
======================================================

**LEGAL NOTICE:** Operating on frequencies outside the unlicensed ISM bands
requires a valid amateur radio license (or equivalent authorization in your
jurisdiction). In the US, this means an FCC Part 97 license (Technician class
or higher). Always comply with your local laws and regulations regarding
radio transmissions, power limits, and station identification requirements.

Goal: Unlock 2312-2732 MHz on ath5k for US Part 97 ham radio use on a
La Fonera FON2100A (Atheros AR2315, 8MB flash, 16MB RAM).

Source: https://github.com/openwrt/archive.git branch attitude_adjustment
Target: atheros (AR231x/AR5312 SoC)
Build: Docker container (Ubuntu 14.04) due to modern GCC incompatibilities

Hardware
--------
- La Fonera FON2100A
- Atheros AR2315 SoC
- 8MB flash, 16MB RAM
- 2.4 GHz only (hardware range: 2312-2732 MHz per AR2315 datasheet)
- Serial console: 3.3V TTL, 9600 baud (or 115200 depending on bootloader)
- EEPROM reports country code US (regdomain 0x3a / FCC3_FCCA)

US Ham Radio Context (13cm band)
---------------------------------
- US Part 97 allocation: 2300-2310 MHz and 2390-2450 MHz
- Gap at 2310-2390 (not allocated to amateur)
- AR2315 hardware minimum is ~2312 MHz, so 2300-2310 is unreachable
- Usable ham range on this hardware: 2390-2450 MHz (overlaps Wi-Fi ch 1+)
- Part 97 requirements: no encryption, must ID with callsign (SSID works)
- AREDN/HSMM convention: negative channel numbers below ch 1 (5 MHz spacing)
  e.g. ch -2 = 2397 MHz center, ch -4 = 2387 MHz center

Why This Build Exists
---------------------
Stock OpenWrt (even with ath5k) restricts frequencies to standard Wi-Fi
channels 1-14 (2412-2484 MHz) through FIVE separate enforcement layers:

1. cfg80211 internal regulatory database (regdb.txt compiled into regdb.c)
2. ath driver EEPROM regdomain push (regulatory_hint("US") from ath5k/base.c)
3. ath driver world regdomain definitions (regd.c macros)
4. ath5k hardware capability range check (caps.c range_2ghz_min = 2412)
5. ath5k channel enumeration loop (base.c starts at ch=1, only standard channels)
6. ath5k_is_standard_channel() filter (rejects ch <= 0 or ch > 14 for 2GHz)
7. hostapd channel config is u8 (unsigned, wraps negative to 254) and
   ieee80211_freq_to_chan() doesn't handle sub-2412 frequencies

ALL of these must be addressed to unlock sub-2412 frequencies.

Changes Made
------------

1. package/mac80211/patches/407-ath_regd_ham_frequencies.patch
   - Widens ATH9K_2GHZ_CH01_11 macro in regd.c from 2402-2472 to 2312-2472
   - Widens ATH9K_2GHZ_CH12_13 macro from 2457-2482 to 2457-2732
   - Also patches reg.c world_regdom (belt-and-suspenders, regdb overrides this)

2. package/mac80211/patches/408-ath5k_disable_reg_hint.patch
   - Guards ath5k/base.c regulatory_hint() call with #ifndef CPTCFG_ATH_USER_REGD
   - Without this, ath5k pushes EEPROM country "US" to cfg80211 on init,
     which locks the regdomain to FCC (2402-2472 only)
   - The existing ATH_USER_REGD patch (403) only guards ath_regd_init_wiphy(),
     but ath5k has its OWN regulatory_hint() call that bypasses it

3. package/mac80211/patches/409-ath5k_extend_2ghz_min.patch
   - Changes ath5k/caps.c range_2ghz_min from 2412 to 2312
   - The source even has a comment "/* 2312 */" suggesting this was intended
   - Without this, ath5k_channel_ok() rejects any freq < 2412

4. package/mac80211/patches/412-ath5k_extended_channels.patch
   - Changes ath5k_setup_channels() loop to start at ch=-20 (2312 MHz)
   - Changes `unsigned int ch` to `int ch` (CRITICAL: unsigned -20 wraps!)
   - Increases size from 26 to 46 for more channel slots
   - Adds frequency calculation: ch<0 uses 2412+(ch*5)
   - ch=0 skipped, ch 1-13 uses 2407+(ch*5), ch14=2484, ch>14 uses kernel helper
   - Patch numbered 412 to apply AFTER existing 411-ath5k_allow_adhoc_and_ap.patch

5. package/mac80211/files/regdb.txt
   - Replaced country 00 2.4GHz rules with single continuous rule:
     (2312 - 2472 @ 40), (30)
   - Start/end are band EDGES, not channel centers
   - A channel center is valid when center +/- (bandwidth/2) fits within edges
   - 40 MHz channels: centers 2332-2452 valid
   - 20 MHz channels: centers 2322-2462 valid
   - 10 MHz channels: centers 2317-2467 valid
   - Split rules cause dead zones at boundaries (learned the hard way)
   - This file is compiled into regdb.c during build (not a runtime file)
   - This is what `iw reg get` actually shows

6. package/mac80211/Makefile
   - Commented out ath10k-firmware download (dead GitHub URL, not needed)
   - Commented out ath10k-firmware tar extraction (line 1542)
   - Added: config-$(call config_package,ath5k) += ATH5K_TEST_CHANNELS
   - ATH5K_TEST_CHANNELS makes ath5k_is_standard_channel() always return true

7. package/hostapd/patches/700-support-negative-channels.patch
   - Changes conf->channel from u8 to int in ap_config.h (u8 wraps -2 to 254)
   - Extends ieee80211_freq_to_chan() to handle 2312-2411 MHz range
   - Changes channel output param from u8* to short* in ieee802_11_common.c/.h
   - Changes local channel var from u8 to short in driver_nl80211.c
   - Formula: channel = (freq - 2407) / 5 (same as standard, works for negatives)
   - This lets hostapd accept channel=-2 in config and correctly map it to 2397 MHz

8. tools/Makefile
   - Commented out b43-tools (Broadcom tool, dead git repo, not needed)

9. package/base-files/files/etc/config/network
   package/base-files/files/etc/preinit
   package/base-files/files/lib/functions/uci-defaults.sh
   - Changed default IP from 192.168.1.1 to 192.168.5.1

10. .config
   - CONFIG_TARGET_atheros=y
   - CONFIG_ATH_USER_REGD=y
   - CONFIG_PACKAGE_luci=y, CONFIG_PACKAGE_uhttpd=y
   - CONFIG_PACKAGE_kmod-ath5k=y

10. feeds.conf
    - src-git luci https://github.com/openwrt/luci.git;luci-0.11
    - Original SVN feeds all dead; LuCI available on GitHub

11. Dockerfile
    - Ubuntu 14.04 build environment
    - ln -sf /bin/tar /usr/bin/tar (OpenWrt scripts hardcode /usr/bin/tar)
    - ln -sf /bin/bash /usr/bin/bash (configure scripts hardcode /usr/bin/bash)

Key Config Options
------------------
- ATH_USER_REGD=y - ath driver defers to user regdomain, skips EEPROM enforcement
- ATH5K_TEST_CHANNELS=y - disables standard channel filter in ath5k
- CFG80211_INTERNAL_REGDB=y - uses compiled-in regdb (generated from regdb.txt)

How It All Fits Together
------------------------
1. ATH_USER_REGD makes ath_regd_init_wiphy() return early (no STRICT_REG, no CUSTOM_REG)
2. Patch 408 prevents ath5k from calling regulatory_hint("US") after registration
3. cfg80211 stays on the built-in world regdomain "00" (never gets overridden)
4. regdb.txt defines "00" with single continuous rule (2312-2472 @ 40MHz, 30dBm)
5. ath5k caps.c allows frequencies down to 2312 (range_2ghz_min)
6. ath5k base.c channel loop generates freqs from 2312 (ch=-20) through 2642 (ch=46)
7. ATH5K_TEST_CHANNELS bypasses the "is this a standard channel?" filter
8. hostapd accepts negative channel numbers (conf->channel is now int, not u8)
9. hostapd's ieee80211_freq_to_chan maps sub-2412 freqs to negative channel numbers
10. Result: `uci set wireless.radio0.channel='-2'` tunes to 2397 MHz on boot

LuCI Web Interface
------------------
- LuCI reads available channels from iwinfo, which queries the kernel
- No LuCI patches needed — if the kernel reports the frequencies, LuCI shows them
- iwinfo's nl80211_freq2channel() will show negative channel numbers for sub-2412
- Channel list is dynamic, not hardcoded in the UI

Usage
-----
After flashing, set channel via UCI:
  uci set wireless.radio0.channel='-2'
  uci set wireless.radio0.chanbw='10'
  uci set wireless.radio0.disabled='0'
  uci set wireless.@wifi-iface[0].ssid='YOURCALL-2397'
  uci set wireless.@wifi-iface[0].encryption='none'
  uci set wireless.@wifi-iface[0].macaddr='XX:XX:XX:XX:XX:XX'
  uci commit wireless
  wifi

Channel -2 = 2397 MHz center (formula: 2407 + channel*5)
At 10 MHz bandwidth: spans 2392-2402 MHz

Bandwidth modes available via debugfs (5/10/20/40 MHz):
  echo "10" > /sys/kernel/debug/ieee80211/phy0/ath5k/bwmode
  (also settable via UCI: wireless.radio0.chanbw='10')

Runtime Configuration Notes
---------------------------
uhttpd (LuCI web server):
  - Default script_timeout increased to 120s (183 MHz CPU is slow)
  - If accessing LuCI from a RFC1918 IP (e.g. 192.168.x.x) while the
    server is on a public IP (44.x.x.x), you'll get "Rejected request
    from RFC1918 IP to public server address". Fix:
    uci add_list uhttpd.main.rfc1918_filter='0'
    uci commit uhttpd
    /etc/init.d/uhttpd restart

DNS:
  - AP's own DNS (for upstream resolution):
    uci set network.lan.dns='your.dns.server'
  - DNS handed to DHCP clients:
    uci set dhcp.@dnsmasq[0].server='8.8.8.8'

MAC address convention (ham radio station ID):
  - Encode callsign as ASCII in the MAC address
  - Example: W1AW-9 = 57:31:41:57:2D:39
  - Set via: uci set wireless.@wifi-iface[0].macaddr='57:31:41:57:2D:39'
  - Clients do the same; AP sees all callsigns in `iw dev wlan0 station dump`
  - Convert: python3 -c "'W1AW-9'.encode('ascii').hex(':')"

Example network setup (routed AP, no NAT):
  # Ethernet uplink on 44net
  uci set network.lan.ipaddr='44.x.x.2'
  uci set network.lan.netmask='255.255.255.192'
  uci set network.lan.gateway='44.x.x.1'
  uci set network.lan.dns='your.dns.server'
  uci del network.lan.type

  # Wifi on routed /28 subnet
  uci set network.wifi=interface
  uci set network.wifi.proto='static'
  uci set network.wifi.ipaddr='44.x.x.129'
  uci set network.wifi.netmask='255.255.255.240'
  uci set wireless.@wifi-iface[0].network='wifi'

  # DHCP for wireless clients
  uci set dhcp.wifi=dhcp
  uci set dhcp.wifi.interface='wifi'
  uci set dhcp.wifi.start='2'
  uci set dhcp.wifi.limit='13'
  uci set dhcp.wifi.leasetime='12h'
  uci set dhcp.lan.ignore='1'

  # Upstream router needs: ip route add 44.x.x.128/28 via 44.x.x.2

Build Instructions
------------------
Requires Docker (Ubuntu 14.04 container needed due to old toolchain).

1. Clone:
   git clone https://github.com/openwrt/archive.git --branch attitude_adjustment --depth 1 openwrt-aa
   cd openwrt-aa

2. Apply patches/config (or use this repo directly if forked).

3. Download sources to dl/ (see Download Sources section below).

4. Build:
   docker build -t openwrt-aa-builder .
   docker run --rm -v "$(pwd)":/home/builder/openwrt -w /home/builder/openwrt openwrt-aa-builder \
     bash -c "./scripts/feeds update luci && ./scripts/feeds install -a && make defconfig && make -j$(nproc) V=s"

   Or simply: ./runme.sh

5. Output in bin/atheros/:
   - openwrt-atheros-vmlinux.lzma (~917KB kernel)
   - openwrt-atheros-root.squashfs (~1.9MB rootfs)
   - Total ~2.9MB, fits comfortably in 8MB flash

6. Copy to TFTP server and flash via serial/RedBoot (see Flashing section below).

Flashing the FON2100A
---------------------
Reference: https://openwrt.org/toh/fon/fonera

The FON2100A uses RedBoot (an eCos-based bootloader from the mid-2000s).
RedBoot manages flash partitions and can load files via TFTP.

Accessing RedBoot:

  Option A - Serial console:
    - 3.3V TTL serial (NOT RS232 levels — will damage the board)
    - Settings: 9600 baud, 8N1
    - Use a USB-to-TTL adapter (FTDI FT232RL or CP2102 at 3.3V)
    - Wiring: Adapter TX->FON RX, Adapter RX->FON TX, GND->GND
    - Do NOT connect VCC (power FON from its own 5V supply)
    - NOTE: On some FON2100 units, you must plug in the serial adapter
      ~3 seconds AFTER powering on, or the device won't boot
    - Press Ctrl+C during boot to interrupt and get RedBoot prompt

  Option B - Telnet (port 9000):
    - Only works if RedBoot was previously configured with an IP address
    - Must send a telnet break sequence during the boot timeout window
    - Create the break sequence file:
      echo -e "\0377\0364\0377\0375\0006" > break
    - Send it (power cycle the device, then quickly run):
      nc 192.168.5.254 9000 < break
    - This sends IAC BREAK IAC WILL TIMING-MARK
    - Default boot timeout is ~1 second but can be increased in RedBoot
      config. With a 10 second timeout you have plenty of time.
    - To configure RedBoot's IP and timeout (from RedBoot prompt):
      fconfig boot_script_timeout 10
      fconfig bootp_my_ip 192.168.5.254
      fconfig bootp_my_ip_mask 255.255.255.0
      fconfig bootp_server_ip 192.168.5.2
      Answer 'n' to "Update RedBoot non-volatile configuration" until
      the last one, then 'y' to write all changes at once.
      This sets a 10-second window for the telnet break, configures
      RedBoot's IP to 192.168.5.254, and sets the default TFTP server.

  Enabling telnet WITHOUT serial access:
    - If you have SSH access to the device (stock FON firmware or existing
      OpenWrt), you can write a pre-made RedBoot config partition that
      enables telnet on port 9000 with a 10-second boot timeout.
    - The file redboot-config.bin in this repo is a raw 4KB flash image
      containing: IP 192.168.5.254/24, server 192.168.5.2, timeout 10s
    - From a running Linux on the FON:
      mtd -e "RedBoot config" write redboot-config.bin "RedBoot config"
      reboot
    - After reboot, you have 10 seconds to send the telnet break:
      nc 192.168.5.254 9000 < break
    - This is how the original FON hack worked (the old out.hex from
      ipkg.k1k2.de, which is now offline). Same concept, updated IPs.

Prerequisites:
  - TFTP server running on your machine
    - atftpd recommended (tftpd-hpa has a bug with AF_UNSPEC sockets
      on modern kernels — use `atftpd --port 69 --bind-address <IP> /srv/tftp`)
  - Firmware files in TFTP root:
    cp bin/atheros/openwrt-atheros-vmlinux.lzma /srv/tftp/
    cp bin/atheros/openwrt-atheros-root.squashfs /srv/tftp/
  - Direct ethernet connection between your machine and the FON2100A
    (or on the same L2 network segment)
  - Your machine's IP set to match what you tell RedBoot (e.g. 192.168.5.2)

RedBoot flash commands (type these at the "RedBoot>" prompt):

  # Set network addresses
  # -h = TFTP server (your machine), -l = RedBoot's own IP
  ip_address -h 192.168.5.2 -l 192.168.5.254/24

  # Download kernel image from TFTP server into RAM
  load -r -b %{FREEMEMLO} openwrt-atheros-vmlinux.lzma

  # Initialize flash partition table (ERASES ALL EXISTING PARTITIONS)
  # Only needed on first flash or if changing partition layout
  fis init

  # Write kernel from RAM to flash
  # -e = ELF entry point, -r = RAM load address (standard for MIPS on this SoC)
  fis create -e 0x80041000 -r 0x80041000 vmlinux.bin.l7

  # Download root filesystem from TFTP server into RAM
  load -r -b %{FREEMEMLO} openwrt-atheros-root.squashfs

  # Write rootfs from RAM to flash
  fis create rootfs

  # Reboot into the new firmware
  reset

Notes:
  - %{FREEMEMLO} is a RedBoot variable pointing to available RAM
  - The device has 8MB flash total; kernel (~917KB) + rootfs (~1.9MB) +
    RedBoot + config + jffs2 overlay all share this space
  - fis init wipes the flash partition table — on subsequent reflashes
    you can skip it if the partition layout hasn't changed, but it's
    safer to always run it
  - The -e and -r flags set the entry point and load address for Linux
  - 0x80041000 is the standard Linux kernel entry for AR2315 MIPS
  - Each TFTP transfer takes ~5-10 seconds over 100Mbit ethernet
  - After reset, the device boots into OpenWrt. First boot takes ~60
    seconds as it initializes the jffs2 overlay partition
  - Default IP after boot: 192.168.5.1 (we changed this from stock 192.168.1.1)
  - SSH (dropbear) is available with no password on first boot — set one immediately
  - LuCI web interface available at http://192.168.5.1

Building on a Modern System (2026) — Problems Solved
-----------------------------------------------------
The original OpenWrt Attitude Adjustment (2013) cannot build on modern Linux:

Problem: GCC 15 rejects old C idioms (bool typedef, implicit declarations, etc.)
  - cmake 2.8.12 fails: 'bool' cannot be defined via 'typedef'
  - sed 4.2.1 fails: freadahead.c #error
  - xz 5.0.4 fails: conflicting types for 'memmove'
  Solution: Build inside Ubuntu 14.04 Docker container (GCC 4.8)

Problem: /usr/bin/tar and /usr/bin/bash don't exist in Ubuntu 14.04
  - OpenWrt scripts hardcode these paths
  Solution: Symlinks in Dockerfile

Problem: scripts/config/conf built on host with newer glibc, won't run in container
  - "GLIBC_2.27 not found" errors
  Solution: Run `make -C scripts/config clean` before building in container,
  or never run make on the host (always use container)

Problem: Original source mirrors are dead (mirror2.openwrt.org partially works)
  - Many tarballs return 404
  - Git repos unreachable (git.bues.ch for b43-tools, git:// protocol blocked)
  Solution: Pre-download to dl/ from alternative sources (see below)

Problem: feeds.conf uses SVN repos that no longer exist
  - svn://svn.openwrt.org is gone
  - LuCI was in a separate SVN feed
  Solution: Use git mirror: src-git luci https://github.com/openwrt/luci.git;luci-0.11

Problem: ath10k-firmware git clone fails (GitHub auth required for git:// protocol)
  Solution: Comment out the Download and extraction in package/mac80211/Makefile
  (not needed for ath5k/AR2315 target anyway)

Problem: b43-tools git clone fails (git.bues.ch down)
  Solution: Comment out in tools/Makefile (Broadcom tool, not needed for Atheros)

Download Sources
----------------
Most packages fetched from: http://mirror2.openwrt.org/sources/
Fallback mirror that sometimes works: https://sources.openwrt.org/

Packages that needed alternative sources:

  linux-3.3.8.tar.bz2
    https://cdn.kernel.org/pub/linux/kernel/v3.x/linux-3.3.8.tar.bz2

  mklibs_0.1.34.tar.gz
    https://snapshot.debian.org/archive/debian/20130101T000000Z/pool/main/m/mklibs/mklibs_0.1.34.tar.gz

  dnsmasq-2.66.tar.gz
    https://web.archive.org/web/2014/http://thekelleys.org.uk/dnsmasq/dnsmasq-2.66.tar.gz

  zlib-1.2.7.tar.bz2
    Downloaded .tar.gz from https://zlib.net/fossils/zlib-1.2.7.tar.gz then recompressed:
    gunzip -c zlib-1.2.7.tar.gz | bzip2 > zlib-1.2.7.tar.bz2

  util-linux-2.21.2.tar.xz
    https://www.kernel.org/pub/linux/utils/util-linux/v2.21/util-linux-2.21.2.tar.xz

  e2fsprogs-1.42.4.tar.gz
    https://sourceforge.net/projects/e2fsprogs/files/e2fsprogs/v1.42.4/e2fsprogs-1.42.4.tar.gz/download

  cloog-ppl-0.15.11.tar.gz
    https://gcc.gnu.org/pub/gcc/infrastructure/cloog-ppl-0.15.11.tar.gz

  mtools-4.0.17.tar.gz
    https://ftp.gnu.org/gnu/mtools/mtools-4.0.17.tar.gz

  bridge-utils-1.5.tar.gz
    https://web.archive.org/web/2014/http://downloads.sourceforge.net/bridge/bridge-utils-1.5.tar.gz

  uClibc++-0.2.4.tar.bz2
    https://cxx.uclibc.org/src/uClibc++-0.2.4.tar.bz2

  hotplug2-201.tar.gz
    http://mirror2.openwrt.org/sources/hotplug2-201.tar.gz

Git-based packages (clone, checkout specific commit, remove .git, tar):

  hostapd-20131120.tar.bz2
    git clone https://w1.fi/hostap.git hostapd-20131120
    cd hostapd-20131120 && git checkout 594516b4c28a94ca686b17f1e463dfd6712b75a7
    rm -rf .git && cd .. && tar cjf hostapd-20131120.tar.bz2 hostapd-20131120

  6relayd-2013-07-26.tar.bz2
    git clone https://github.com/sbyx/6relayd.git 6relayd-2013-07-26
    cd 6relayd-2013-07-26 && git checkout 2ed520c500b0fbb484cfad5687eb39a0da43dcf7
    rm -rf .git && cd .. && tar cjf 6relayd-2013-07-26.tar.bz2 6relayd-2013-07-26

  odhcp6c-2013-10-02.tar.bz2
    git clone https://github.com/sbyx/odhcp6c.git odhcp6c-2013-10-02
    cd odhcp6c-2013-10-02 && git checkout 357ecc1f5163bc7f74c64f4bca387e8d44a2eac5
    rm -rf .git && cd .. && tar cjf odhcp6c-2013-10-02.tar.bz2 odhcp6c-2013-10-02

Differences from Stock Attitude Adjustment Image
-------------------------------------------------
Compared the stock archive image (openwrt-atheros-root.squashfs from
https://archive.openwrt.org/attitude_adjustment/12.09/atheros/generic/)
to our build:

- Firewall: old shell-based (/lib/firewall/, /sbin/fw) -> new fw3 binary
- JSON lib: libjson.so.0 -> libjson-c.so.2
- Added: libip6tc.so (IPv6 iptables), gpio-button-hotplug.ko
- Removed: gpioctl binary (replaced by kernel module)
- LuCI: slightly different module layout (added ipv6.lua)
- Added: libiwinfo/hardware.txt, readlink binary
- sysctl init: moved from S99 to S11
- Default IP: 192.168.1.1 -> 192.168.5.1
- Size: 7.0MB -> 7.3MB extracted (both fit in 8MB flash fine)
- Kernel: patched mac80211/ath5k/cfg80211 for extended frequencies
