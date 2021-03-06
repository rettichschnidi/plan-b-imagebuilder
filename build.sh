#!/bin/bash
#
# A very simple one-shot script to build a Plan B image
#

set -eu -o pipefail

readonly topdir="$(cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
readonly dl_dir="${topdir}/dl"
readonly build_dir="${topdir}/build_dir"
readonly files_dir="${topdir}/plan-b-openwrt-config/files"

check_sha256sum() {
  local readonly full_path="$1"
  local readonly checksum_expected="$2"
  local readonly checksum_actual="$(sha256sum ${full_path} | awk '{print $1}')"
  if [ ${checksum_expected} != ${checksum_actual} ]; then
    echo "${full_path} does not match the expected checksum"
    exit 1
  fi
}

download_file() {
  local readonly url="$1"
  local readonly filename="$2"
  local readonly sha256sum="$3"
  mkdir -p "${dl_dir}"
  (
    cd "${dl_dir}"
    wget ${url} -N -c
    check_sha256sum "${filename}" ${sha256sum}
  )
}

extract_archive() {
  local readonly filename="$1"
  mkdir -p "${build_dir}"
  tar xf "${dl_dir}/${filename}" -C "${build_dir}"
}

if [ $# -eq 0 ]; then
  echo 'No device specified!' >&2
  exit 1
fi

readonly device=$1

case $device in
    gl-ar150)
      readonly base_url=https://downloads.openwrt.org/releases/17.01.4/targets/ar71xx/generic
      readonly sdk_dirname=lede-sdk-17.01.4-ar71xx-generic_gcc-5.4.0_musl-1.1.16.Linux-x86_64
      readonly sdk_archive_sha256sum=89a5d8f176ee7b647b377c993e3e49841cb1f8d1e2a3d5e286f0a6ce7c5cde28
      readonly imagebuilder_dirname=lede-imagebuilder-17.01.4-ar71xx-generic.Linux-x86_64
      readonly imagebuilder_archive_sha256sum=532d5011c46e9f77a687480a07d9a1e55657311a77c83d14651449c69820509c
      readonly arch=mips_24kc
      ;;
    gl-mt300a)
      readonly base_url=https://downloads.openwrt.org/releases/17.01.4/targets/ramips/mt7620
      readonly sdk_dirname=lede-sdk-17.01.4-ramips-mt7620_gcc-5.4.0_musl-1.1.16.Linux-x86_64
      readonly sdk_archive_sha256sum=da2604d28eb1f0bf320cdad0b2a76cba8e4194b515105e151b0ebbc39dc34f53
      readonly imagebuilder_dirname=lede-imagebuilder-17.01.4-ramips-mt7620.Linux-x86_64
      readonly imagebuilder_archive_sha256sum=79a6cd335c0f490dce046ef555ba2457c04dfde687b7d604a598eeffe0b0e743
      readonly arch=mipsel_24kc
      ;;
    *)
      echo "Unknown device: ${device}" >&2
      exit 1
esac

readonly sdk_dirname_full="${build_dir}/${sdk_dirname}"
readonly sdk_archive=${sdk_dirname}.tar.xz
download_file ${base_url}/${sdk_archive} ${sdk_archive} ${sdk_archive_sha256sum}
extract_archive ${sdk_archive}

(
  cp sdk.config "${sdk_dirname_full}/.config"
  cd "${sdk_dirname_full}"
  egrep "base|packages" feeds.conf.default > feeds.conf
  echo src-git plan_b https://github.com/rettichschnidi/plan-b-openwrt-custom-packages.git^316b13fee154a8812eea7d6a640cf6890541eab5 >> feeds.conf
  ./scripts/feeds update base packages plan_b
  ./scripts/feeds install -p plan_b -a -d y
  make defconfig
  make
)

readonly imagebuilder_dirname_full=${build_dir}/${imagebuilder_dirname}
readonly imagebuilder_archive=${imagebuilder_dirname}.tar.xz
download_file ${base_url}/${imagebuilder_archive} ${imagebuilder_archive} ${imagebuilder_archive_sha256sum}
extract_archive ${imagebuilder_archive}

(
  readonly extra_image_name=plan-b-$(git describe --dirty --always)
  cd "${imagebuilder_dirname_full}"
  echo "src sdk file:${sdk_dirname_full}/bin/packages/${arch}/plan_b" >> repositories.conf
  make image PROFILE=${device} EXTRA_IMAGE_NAME=${extra_image_name} PACKAGES="-wpa_supplicant -ppp -ppp-mod-pppoe libustream-openssl plan-b-tor iperf3 curl ca-certificates ca-bundle kmod-usb-storage kmod-fs-msdos kmod-fs-ext4 block-mount" FILES="${files_dir}"
)
