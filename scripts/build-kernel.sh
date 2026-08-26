#!/bin/sh

# Build an ARM64 Image with the exact Android clang family used by stock. The
# intermediate tree stays in a Docker volume and only final artifacts are
# copied to the private sibling work directory.

set -eu

kernel_dir="${KERNEL_DIR:-/work/kernel}"
toolchain_dir="${TOOLCHAIN_DIR:-/work/toolchain/clang-r383902}"
output_dir="${OUTPUT_DIR:-/work/build/rt7}"
source_config="${SOURCE_CONFIG:-/rt7-work/build/kernel/config-test/.config}"
artifact_dir="${ARTIFACT_DIR:-/rt7-work/build/kernel/artifacts}"
jobs="${JOBS:-$(nproc)}"

if [ ! -d "$kernel_dir/.git" ]; then
    printf 'error: kernel source not prepared: %s\n' "$kernel_dir" >&2
    exit 1
fi

if [ ! -x "$toolchain_dir/bin/clang" ]; then
    printf 'error: clang toolchain not prepared: %s\n' "$toolchain_dir" >&2
    exit 1
fi

if [ ! -r "$source_config" ]; then
    printf 'error: resolved kernel config not readable: %s\n' "$source_config" >&2
    exit 1
fi

/bin/sh /project/scripts/apply-kernel-patches.sh

export PATH="$toolchain_dir/bin:$PATH"
export KBUILD_BUILD_USER='rt7-linux'
export KBUILD_BUILD_HOST='reproducible'
export KBUILD_BUILD_VERSION="${KBUILD_BUILD_VERSION:-1}"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$kernel_dir" show -s --format=%ct HEAD)}"
export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-$(git -C "$kernel_dir" show -s --format=%cD HEAD)}"
# The generated OPPO feature file names this kernel-4.19 product, but the
# variable is not exported into recursive makes in a standalone checkout.
export TARGET_PRODUCT='vnd_k6893v1_64_k419'

# CONFIG_DEBUG_INFO records the out-of-tree build directory. LLD's fast build
# ID hashes those non-loadable debug sections, which otherwise changes both
# the VDSO and kernel build IDs when O= changes even though the loaded bytes are
# identical. Map every disposable output path to one canonical path.
canonical_build_path=${CANONICAL_BUILD_PATH:-/rt7-kernel-build}
path_map_flag="-ffile-prefix-map=$output_dir=$canonical_build_path"
export KCFLAGS="${KCFLAGS:+$KCFLAGS }$path_map_flag"
export KAFLAGS="${KAFLAGS:+$KAFLAGS }$path_map_flag"

mkdir -p "$output_dir" "$artifact_dir"
cp "$source_config" "$output_dir/.config"

make -C "$kernel_dir" \
    O="$output_dir" \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    olddefconfig

make -C "$kernel_dir" \
    O="$output_dir" \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    CROSS_COMPILE=aarch64-linux-gnu- \
    -j "$jobs" \
    Image

cp "$output_dir/arch/arm64/boot/Image" "$artifact_dir/Image"
gzip -9 -n -c "$output_dir/arch/arm64/boot/Image" > "$artifact_dir/Image.gz"
cp "$output_dir/System.map" "$artifact_dir/System.map"
cp "$output_dir/.config" "$artifact_dir/kernel.config"

(
    cd "$artifact_dir"
    sha256sum Image Image.gz System.map kernel.config > SHA256SUMS
    cat SHA256SUMS
)
