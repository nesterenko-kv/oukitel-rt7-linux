#!/bin/sh

# Merge the stock kernel config with the public Docker fragments and resolve
# their Kconfig dependencies using the pinned kernel source tree.

set -eu

kernel_dir="${KERNEL_DIR:-/work/kernel}"
output_dir="${OUTPUT_DIR:-/rt7-work/build/kernel/config-test}"
stock_config_gz="${STOCK_CONFIG_GZ:-/rt7-work/device-dumps/stock-config.gz}"
modules_dir="${MODULES_DIR:-/work/modules}"
oppo_defconfig="${OPPO_DEFCONFIG:-$kernel_dir/arch/arm64/configs/k6853v1_64_6360_k419_defconfig}"

if [ ! -d "$kernel_dir" ]; then
    printf 'error: kernel source not found: %s\n' "$kernel_dir" >&2
    exit 1
fi

if [ ! -r "$stock_config_gz" ]; then
    printf 'error: stock config not readable: %s\n' "$stock_config_gz" >&2
    exit 1
fi

if [ ! -d "$modules_dir/vendor" ]; then
    printf 'error: external kernel modules not found: %s/vendor\n' "$modules_dir" >&2
    exit 1
fi

if [ ! -r "$oppo_defconfig" ]; then
    printf 'error: OPPO MT6853 defconfig not readable: %s\n' "$oppo_defconfig" >&2
    exit 1
fi

mkdir -p "$output_dir"
gzip -dc "$stock_config_gz" > "$output_dir/stock.config"
sed -n '/^CONFIG_OPLUS_/p' "$oppo_defconfig" > "$output_dir/oppo-source.config"

"$kernel_dir/scripts/kconfig/merge_config.sh" \
    -m \
    -O "$output_dir" \
    "$output_dir/stock.config" \
    "$output_dir/oppo-source.config" \
    /project/configs/source-compat.config \
    /project/configs/docker-required.config \
    /project/configs/docker-recommended.config

make -C "$kernel_dir" ARCH=arm64 O="$output_dir" olddefconfig

printf 'merged kernel config: %s/.config\n' "$output_dir"
