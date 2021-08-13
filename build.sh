#!/bin/sh

# get the source
curl https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz -o openssl-${OPENSSL_VERSION}.tar.gz
tar xf openssl-${OPENSSL_VERSION}.tar.gz

patch -p0 < openssl-${OPENSSL_VERSION}.patch

cd openssl-${OPENSSL_VERSION}

# why ./Configure instead of ./config? We want to force using the generic gcc profile which is more conservative than linux-x32
# -no-sock - we don't have sockets in WASI
# new -no-ui-console - sdk 12 has no termios???
# check in 12 -DHAVE_FORK=0 - no fork() in WASI
# new -D_WASI_EMULATED_MMAN - works with the library below to enable WASI mman emulation
# new -D_WASI_EMULATED_SIGNAL - with sdk 12
# new -DOPENSSL_NO_SECURE_MEMORY - wasi doesn't have secure mem (madvise, mlock, etc...)
# new -DNO_SYSLOG - get rid of need for patch above
# --with-rand-seed=getrandom (needed to force using getentropy because WASI has no /dev/random or getrandom)
wasiconfigure ./Configure gcc -no-sock -no-ui-console -DHAVE_FORK=0 -D_WASI_EMULATED_MMAN -D_WASI_EMULATED_SIGNAL -DOPENSSL_NO_SECURE_MEMORY -DNO_SYSLOG --with-rand-seed=getrandom

# enables stuff from mman.h (see define above) also add -lwasi-emulated-signal
sed -i -e "s/CNF_EX_LIBS=/CNF_EX_LIBS=-lwasi-emulated-mman -lwasi-emulated-signal /g" Makefile

# build!
wasimake make

# wasirun doesn't add the mapdir and we need it, so replace wasirun with running
# wasmer directly
# TODO: fix wasirun to add mapdir automatically (or with a switch)
sed -i 's|wasirun|wasmer run --enable-all --dir=. --mapdir=/build/openssl-${OPENSSL_VERSION}:/build/openssl-${OPENSSL_VERSION}|' apps/openssl
sed -i 's|\.wasm |\.wasm -- |' apps/openssl
# now the tests
grep -lr wasirun test/* | xargs sed -i 's|wasirun|wasmer run --enable-all --dir=. --mapdir=/build/openssl-${OPENSSL_VERSION}:/build/openssl-${OPENSSL_VERSION}|'
grep -lr wasmer test/* | xargs sed -i 's|\.wasm |\.wasm -- |'
# also pass the entire environment to wasmer during testing
# TODO: add a switch to wasmer to do this
grep -lr wasmer test/* | xargs sed -i 's|--enable-all|--enable-all $\(python -c '\''import os;print reduce\(lambda x, y: x+" --env="+y[0]+"="+y[1], filter\(lambda x: False if "=" in x[1] or not x[1] else True, os.environ.items\(\)\), "")'\'')|'

# sysdefaulttest also needs: --env=OPENSSL_CONF="$OPENSSL_CONF"
# ssl_test also needs:  --env=TEST_CERTS_DIR="$TEST_CERTS_DIR" --env=CTLOG_FILE="$CTLOG_FILE"

# Testing -test_errstr: this will always fail because of linux/wasi mismatches -
# TODO: not needed if we fix cross compile in configdata.pm
make TESTS="-test_errstr" test
