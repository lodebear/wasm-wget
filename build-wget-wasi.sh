#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WASI_SDK_PATH="${WASI_SDK_PATH:-${WASI_SDK_ROOT:-}}"
WASI_LIBC_ROOT="${WASI_LIBC_ROOT:-${ROOT}/../wasi-libc}"
SYSROOT="${WASI_SYSROOT:-${WASI_LIBC_ROOT}/sysroot-monocp}"
OPENSSL_WASM_ROOT="${OPENSSL_WASM_ROOT:-${ROOT}/../openssl-wasm}"

if [[ -z "${WASI_SDK_PATH}" ]]; then
  echo "Set WASI_SDK_PATH (or WASI_SDK_ROOT) to your wasi-sdk install."
  exit 1
fi

if [[ ! -d "${SYSROOT}" ]]; then
  echo "Sysroot not found at ${SYSROOT}. Build wasi-libc first."
  exit 1
fi

if [[ ! -f "${SYSROOT}/lib/wasm32-wasip1/libssl.a" ]] || [[ ! -f "${SYSROOT}/lib/wasm32-wasip1/libcrypto.a" ]]; then
  echo "OpenSSL libs not found in sysroot. Run ${WASI_LIBC_ROOT}/install-openssl-wasm.sh (from ${OPENSSL_WASM_ROOT})."
  exit 1
fi

CC="${WASI_SDK_PATH}/bin/clang --target=wasm32-wasip1 --sysroot=${SYSROOT}"
AR="${WASI_SDK_PATH}/bin/llvm-ar"
RANLIB="${WASI_SDK_PATH}/bin/llvm-ranlib"
STRIP="${WASI_SDK_PATH}/bin/llvm-strip"

CFLAGS="${CFLAGS:-} -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_GETPID"
CPPFLAGS="${CPPFLAGS:-} -D_WASI_EMULATED_SIGNAL -D_WASI_EMULATED_PROCESS_CLOCKS -D_WASI_EMULATED_GETPID -I${SYSROOT}/include"
LDFLAGS="${LDFLAGS:-} -L${SYSROOT}/lib/wasm32-wasip1 -lwasi-emulated-signal -lwasi-emulated-process-clocks -lwasi-emulated-getpid"
PKG_CONFIG="${PKG_CONFIG:-$(command -v pkg-config || echo /usr/bin/pkg-config)}"
PKG_CONFIG_LIBDIR="${PKG_CONFIG_LIBDIR:-/nonexistent}"
PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}"

export CC AR RANLIB STRIP CFLAGS CPPFLAGS LDFLAGS PKG_CONFIG PKG_CONFIG_LIBDIR PKG_CONFIG_PATH

BUILD_DIR="${ROOT}/build-wasi"
mkdir -p "${BUILD_DIR}"

cd "${ROOT}"
if [[ ! -f configure ]]; then
  ./bootstrap
fi

cd "${BUILD_DIR}"
"${ROOT}/configure" \
  --host=wasm32-wasip1 \
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

echo "Built wget wasm binary in ${BUILD_DIR}/src/wget"
