#!/usr/bin/env sh

DEBOS_CMD=debos
device="pinephone"
image="image"
partitiontable="gpt"
filesystem="ext4"
environment="phosh"
crypt_root=
crypt_password=
hostname="kali"
arch="arm64"
do_compress=
family=
image_only=
installer=
zram=
memory=
mirror="http://http.kali.org/kali"
password="1234"
use_docker=
username="kali"
no_blockmap=
ssh=
debian_suite="kali-rolling"
suite="trixie"
contrib="true"
sign=
miniramfs=
version=$( date +%Y%m%d )
verbose=

if [ -z "${ARGS+x}" ]; then
  ARGS=""
fi

export PATH="/sbin:/usr/sbin:${PATH}"

while getopts "cdDvizobsZCrR:x:S:e:H:f:g:h:m:M:p:t:u:F:V:" opt; do
  case "${opt}" in
    c ) crypt_root=1 ;;
    R ) crypt_password=${OPTARG} ;;
    d ) use_docker=1 ;;
    D ) debug=1 ;;
    v ) verbose=1 ;;
    e ) environment="${OPTARG}" ;;
    H ) hostname="${OPTARG}" ;;
    i ) image_only=1 ;;
    z ) do_compress=1 ;;
    b ) no_blockmap=1 ;;
    s ) ssh=1 ;;
    o ) installer=1 ;;
    Z ) zram=1 ;;
    f ) ftp_proxy="${OPTARG}" ;;
    h ) http_proxy="${OPTARG}" ;;
    g ) sign="${OPTARG}" ;;
    M ) mirror="${OPTARG}" ;;
    m ) memory="${OPTARG}" ;;
    p ) password="${OPTARG}" ;;
    t ) device="${OPTARG}" ;;
    u ) username="${OPTARG}" ;;
    F ) filesystem="${OPTARG}" ;;
    x ) debian_suite="${OPTARG}" ;;
    S ) suite="${OPTARG}" ;;
    C ) contrib=1 ;;
    r ) miniramfs=1 ;;
    V ) version="${OPTARG}" ;;
    * )
      echo "Unknown option '${opt}'" 1>&2
      exit 1
      ;;
  esac
done

case "${device}" in
  "pinephone"|"pinetab"|"sunxi" )
    family="sunxi"
    ARGS="${ARGS} -t nonfree:true"
    ;;
  "pinephonepro"|"pinetab2"|"rockchip" )
    family="rockchip"
    ARGS="${ARGS} -t nonfree:true"
    ;;
  "librem5" )
    family="librem5"
    ARGS="${ARGS} -t bootstart:8MiB"
    ;;
  "qcom"|"sdm845"|"sm7225"|"qcom-wip" )
    if [ "${device}" = "qcom-wip" ]; then
      device="wip"
    fi
    family="qcom"
    SECTSIZE="$(tomlq -r '.bootimg.pagesize' devices/qcom/configs/${device}.toml)"
    ARGS="${ARGS} -e MKE2FS_DEVICE_SECTSIZE:${SECTSIZE} -t nonfree:true -t bootonroot:true"
    ;;
  "amd64"|"amd64-free" )
    arch="amd64"
    family="amd64"
    ARGS="${ARGS} -t imagesize:15GB -t installersize:10GB"
    if [ "${device}" = "amd64" ]; then
      ARGS="${ARGS} -t nonfree:true"
    fi
    ;;
  * )
    echo "Unsupported device '${device}' "1>&2
    echo "Supported devices: pinephone, pinephonepro, pinetab, pinetab2, sdm845, sm7225, amd64"
    exit 1
    ;;
esac

installfs_file="installfs-${arch}.tar.gz"

image_file="nethunterpro-${version}-${device}-${environment}"
if [ "$installer" ]; then
  image="installer"
  image_file="${image_file}-${image}"
fi

rootfs_file="rootfs-${arch}-${environment}.tar.gz"
if echo "${ARGS}" | grep -q "nonfree:true"; then
  rootfs_file="rootfs-${arch}-${environment}-nonfree.tar.gz"
fi

## Cleanup previous artifacts if we're not re-using them
if [ ! "${image_only}" ]; then
  rm -vf "${rootfs_file}" \
         "${installfs_file}" \
         "rootfs-${device}-${environment}.tar.gz"
fi

if [ "${use_docker}" ]; then
  DEBOS_CMD=docker
  ARGS="run \
            --rm \
            --interactive \
            --tty \
            --device /dev/kvm \
            --workdir /recipes \
            --mount type=bind,source=$(pwd),destination=/recipes \
            --security-opt label=disable \
            godebos/debos \
            ${ARGS}"
fi

[ "${debug}" ] && ARGS="${ARGS} --debug-shell"
[ "${verbose}" ] && ARGS="${ARGS} --verbose"
[ "${username}" ] && ARGS="${ARGS} -t username:${username}"
## Must remain above password otherwise ${password} will override this
[ "${crypt_password}" ] && ARGS="${ARGS} -t crypt_password:${crypt_password}"
[ "${password}" ] && ARGS="${ARGS} -t password:${password}"
[ "${ssh}" ] && ARGS="${ARGS} -t ssh:${ssh}"
[ "${environment}" ] && ARGS="${ARGS} -t environment:${environment}"
[ "${hostname}" ] && ARGS="${ARGS} -t hostname:${hostname}"
[ "${http_proxy}" ] && ARGS="${ARGS} -e http_proxy:${http_proxy}"
[ "${ftp_proxy}" ] && ARGS="${ARGS} -e ftp_proxy:${ftp_proxy}"
[ "${memory}" ] && ARGS="${ARGS} --memory ${memory}"
[ "${mirror}" ] && ARGS="${ARGS} -t mirror:${mirror}"
[ "${miniramfs}" ] && ARGS="${ARGS} -t miniramfs:true"
[ "${contrib}" ] && ARGS="${ARGS} -t contrib:true"
[ "${zram}" ] && ARGS="${ARGS} -t zram:true"
[ "${crypt_root}" ] && ARGS="${ARGS} -t crypt_root:true"

ARGS="${ARGS} \
            -t architecture:${arch} \
            -t family:${family} \
            -t device:${device} \
            -t partitiontable:${partitiontable} \
            -t filesystem:${filesystem} \
            -t image:${image_file} \
            -t rootfs:${rootfs_file} \
            -t installfs:${installfs_file} \
            -t debian_suite:${debian_suite} \
            -t suite:${suite} \
            --scratchsize=8G"

if [ ! "${image_only}" ] || [ ! -f "${rootfs_file}" ]; then
  ## Ensure subsequent artifacts are rebuilt too
  rm -vf "rootfs-${device}-${environment}.tar.gz"
  ${DEBOS_CMD} ${ARGS} rootfs.yaml || exit 1
fi

if [ "$installer" ]; then
  if [ ! "${image_only}" ] || [ ! -f "${installfs_file}" ]; then
    ${DEBOS_CMD} ${ARGS} installfs.yaml || exit 1
  fi

  if [ ! "${image_only}" ] || [ ! -f "rootfs-${device}-${environment}.tar.gz" ]; then
    ${DEBOS_CMD} ${ARGS} "rootfs-device.yaml" || exit 1
  fi

  ## Convert rootfs tarball to squashfs for inclusion in the installer image
  zcat "rootfs-${device}-${environment}.tar.gz" | tar2sqfs "rootfs-${device}-${environment}.sqfs" > /dev/null 2>&1
fi

${DEBOS_CMD} ${ARGS} "$image.yaml"

if [ "$installer" ]; then
  rm -vf "rootfs-${device}-${environment}.sqfs"
fi

if [ ! "$no_blockmap" ] && [ -f "$image_file.img" ]; then
  bmaptool create "$image_file.img" > "$image_file.img.bmap"
fi

if [ "$do_compress" ]; then
  echo "Compressing ${image_file}..."
  [ -f "${image_file}.img" ] \
    && xz --compress --keep --force "${image_file}.img"
  [ -f "${image_file}.rootfs.img" ] \
    && tar cJf "${image_file}.tar.xz" "${image_file}".*.img
fi

if [ -n "$sign" ]; then
  truncate -s0 "${image_file}.sha256sums"
  if [ "$do_compress" ]; then
    extensions="img.xz tar.xz img.bmap"
  else
    extensions="*.img"
  fi

  for ext in ${extensions}; do
    for file in "${image_file}".${ext}; do
      sha256sum "${file}" >> "${image_file}.sha256sums"
    done
  done

  [ -f "${image_file}.sha256sums".asc ] \
    && rm -v "${image_file}.sha256sums.asc"
  gpg -u "${sign}" --clearsign "${image_file}.sha256sums"
fi
