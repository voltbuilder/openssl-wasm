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
# TODO: it would be nice is wasmer allowed us to specify a starting dir - --dir
#       is not that, but weirdly --dir=. sort of seems to accomplish that,
#       then I could map / and just start in the cwd
sed -i 's|wasirun|wasmer run --enable-all --dir=. --mapdir=/build/openssl-${OPENSSL_VERSION}:/build/openssl-${OPENSSL_VERSION}|' apps/openssl
# additionally map /dev because it's needed for some tests (this'll be removed
# when cross compile is fixed - see below)
sed -i 's|--enable-all|--enable-all --mapdir=/dev:/dev|' apps/openssl
sed -i 's|\.wasm |\.wasm -- |' apps/openssl
# now the tests
# sslapitest needs /tmp mapped, so just map it for everything
grep -lr wasirun test/* | xargs sed -i 's|wasirun|wasmer run --enable-all --dir=. --mapdir=/tmp:/tmp --mapdir=/build/openssl-${OPENSSL_VERSION}:/build/openssl-${OPENSSL_VERSION}|'
grep -lr wasmer test/* | xargs sed -i 's|\.wasm |\.wasm -- |'
# also pass the entire environment to wasmer
# TODO: add a switch to wasmer to do this
sed -i '/^wasmer run.*/i args=\(\); for v in $\(compgen -e\); do if [[ ${!v} == "" ]]; then continue; fi; args+=\( --env="$v=${!v}" \); done' apps/openssl
sed -i 's/--enable-all/--enable-all "${args[@]}"/' apps/openssl
# now the tests
grep -lr wasmer test/* | xargs sed -i '/^wasmer run.*/i args=\(\); for v in $\(compgen -e\); do if [[ ${!v} == "" ]]; then continue; fi; args+=\( --env="$v=${!v}" \); done'
grep -lr wasmer test/* | xargs sed -i 's/--enable-all/--enable-all "${args[@]}"/'

# Testing -test_errstr: this will always fail because of linux/wasi mismatches -
# TODO: not needed if we fix cross compile in configdata.pm
# rehash triggers a permission denied error in WASI for some tests - needs investigation
# test_x509_store - depends on rehash working
# test_ca - calls to rename appear to be broken for missing files in WASI
make TESTS="-test_rehash -test_x509_store -test_ca -test_errstr" test
