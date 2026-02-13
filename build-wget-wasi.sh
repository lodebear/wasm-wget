#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASI_SDK_PATH="${WASI_SDK_PATH:-${WASI_SDK_ROOT:-}}"
WASI_LIBC_ROOT="${WASI_LIBC_ROOT:-${ROOT}/../wasi-libc}"
WASI_TARGET="${WASI_TARGET:-wasm32-wasip2}"
OPENSSL_WASM_ROOT="${OPENSSL_WASM_ROOT:-${ROOT}/../openssl-wasm}"

case "${WASI_TARGET}" in
  wasm32-wasip1)
    DEFAULT_SYSROOT="${WASI_LIBC_ROOT}/sysroot-wasip1"
    DEFAULT_BUILD_DIR="${ROOT}/build-wasi"
    ;;
  wasm32-wasip2)
    DEFAULT_SYSROOT="${WASI_LIBC_ROOT}/sysroot-wasip2"
    DEFAULT_BUILD_DIR="${ROOT}/build-wasip2"
    ;;
  *)
    DEFAULT_SYSROOT="${WASI_LIBC_ROOT}/sysroot-${WASI_TARGET}"
    DEFAULT_BUILD_DIR="${ROOT}/build-${WASI_TARGET}"
    ;;
esac

SYSROOT="${WASI_SYSROOT:-${DEFAULT_SYSROOT}}"
BUILD_DIR="${WGET_BUILD_DIR:-${DEFAULT_BUILD_DIR}}"

if [[ -z "${WASI_SDK_PATH}" ]]; then
  echo "Set WASI_SDK_PATH (or WASI_SDK_ROOT) to your wasi-sdk install."
  exit 1
fi

if [[ ! -d "${SYSROOT}" ]]; then
  echo "Sysroot not found at ${SYSROOT}. Build wasi-libc first."
  exit 1
fi

if [[ ! -f "${SYSROOT}/lib/${WASI_TARGET}/libssl.a" ]] || [[ ! -f "${SYSROOT}/lib/${WASI_TARGET}/libcrypto.a" ]]; then
  echo "OpenSSL libs not found in ${SYSROOT}/lib/${WASI_TARGET}."
  echo "Run ${WASI_LIBC_ROOT}/install-openssl-wasm.sh (from ${OPENSSL_WASM_ROOT}) with WASI_TARGET=${WASI_TARGET}."
  exit 1
fi

CC="${WASI_SDK_PATH}/bin/clang --target=${WASI_TARGET} --sysroot=${SYSROOT}"
AR="${WASI_SDK_PATH}/bin/llvm-ar"
RANLIB="${WASI_SDK_PATH}/bin/llvm-ranlib"
STRIP="${WASI_SDK_PATH}/bin/llvm-strip"

CFLAGS="${CFLAGS:-} -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_GETPID"
CPPFLAGS="${CPPFLAGS:-} -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_GETPID -I${SYSROOT}/include -I${SYSROOT}/include/${WASI_TARGET}"
LDFLAGS="${LDFLAGS:-} -L${SYSROOT}/lib/${WASI_TARGET} -lwasi-emulated-signal -lwasi-emulated-process-clocks -lwasi-emulated-getpid"
PKG_CONFIG="${PKG_CONFIG:-$(command -v pkg-config || echo /usr/bin/pkg-config)}"
PKG_CONFIG_LIBDIR="${PKG_CONFIG_LIBDIR:-/nonexistent}"
PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}"

export CC AR RANLIB STRIP CFLAGS CPPFLAGS LDFLAGS PKG_CONFIG PKG_CONFIG_LIBDIR PKG_CONFIG_PATH

mkdir -p "${BUILD_DIR}"

cd "${ROOT}"
if [[ ! -f configure ]]; then
  ./bootstrap
fi

cd "${BUILD_DIR}"
"${ROOT}/configure" \
  --host="${WASI_TARGET}" \
  --build="$("${ROOT}/build-aux/config.guess")" \
  --disable-nls \
  --with-ssl=openssl \
  --with-libssl-prefix="${SYSROOT}" \
  --without-zlib \
  --without-libpsl \
  --disable-pcre \
  --disable-pcre2 \
  --disable-iri \
  --disable-opie

make -C "${BUILD_DIR}/lib" -j
make -C "${BUILD_DIR}/src" -j

echo "Built ${WASI_TARGET} wget component in ${BUILD_DIR}/src/wget"
