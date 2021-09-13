# openssl.wasm

OpenSSL compiled for WASM. This passes nearly all of the test suite and attempts to stick as closely as possible to the standard build process. The entire process is documented below.

We've done our best to verify this implementation is secure, and we've been using it in our own [product](https://volt.build/VoltSigner/) for months with no issues.

## Rationale

You might wonder what makes this different from a few other existing implementations of OpenSSL for WASM:

* Maintained - this implementation supports the latest 1.1.1 release, and will support 3.0.0 soon. 
* Documented - all the choices made when building are documented below.
* Passes tests - nearly the entire OpenSSL test suite is passing, and work continues to bring that to 100% by submitting patches to upstream projects.

## Releases

A prebuilt `openssl.wasm` file can be downloaded from https://github.com/voltbuilder/openssl-wasm/releases

## Building Locally

Building locally requires a working docker install. After cloning the repo you can build and test locally using the following commands:

```sh
# create the docker image
docker build . --file Dockerfile --tag openssl-wasm:latest
# build and test openssl.wasm
docker run --name openssl-wasm-container openssl-wasm
# copy build product to the local filesystem
docker cp openssl-wasm-container:/build/openssl.wasm .
# cleanup
docker rm openssl-wasm-container
```

## Build Process

The build process requires some deviations from the standard build process, but aside from using wasienv, uses the same methodology.

### Environment

A forked version of [wasienv](https://github.com/artlogic/wasienv/blob/artlogic/README.md#note) is used for building OpenSSL. The project is built inside of the [docker container](https://hub.docker.com/r/artlogical/wasienv) included with wasienv. Additional build dependencies:

* `build-essential`
* `libfindbin-libs-perl`

### Patches

Some minor patching is required to compile openssl.wasm. Each of the patches are explained below:

* `test/run_tests.pl` and `util/perl/OpenSSL/Test.pm` - use absolute paths while testing due to current wasmer limitations.
* `test/drbgtest.c` - implement HAVE_FORK consistently (as in the rest of the code base) for this test. This should likely be submitted as a patch to openssl.
* `crypto/rand/rand_unix.c` - This patch is the one I'm least sure of. WASI implements `getentropy`, but it seems the compiler flags aren't properly set. I believe this could be fixed with a smaller patch, but I'm not sure how yet.

### Configuring the Build

`wasiconfigure` is used to wrap the configuration per wasienv conventions. Differences from a standard configure are documented below:

* Use `./Configure` instead of `./config`, which forces a generic gcc profile, instead of the more liberal linux-x32
* Flags:
   * `-no-sock` - no sockets in WASI
   * `-no-ui-console` - termios was removed in SDK 12, unsure why
   * `-DHAVE_FORK=0` - no forking in WASI
   * `-D_WASI_EMULATED_MMAN` - use WASI emulated mman
   * `-D_WASI_EMULATED_SIGNAL` - use WASI emulated signal
   * `-DOPENSSL_NO_SECURE_MEMORY` - WASI doesn't have secure memory (madvise, mlock, etc...)
   * `-DNO_SYSLOG` - No syslog in WASI
   * `--with-rand-seed=getrandom` - combined with the patch above, forces OpenSSL to use WASI's entropy sources

Additionally, the generated Makefile is patched to include libraries to support the WASI emulated functions listed above.

### Building

`wasimake` is used to run `make`. After the build is complete several of the resulting wasienv generated shell scripts are modified in the following ways:

* `wasmer` is used directly instead of `wasirun` so flags can be passed to wasmer as needed (this could eventually become unnecessary with patches to wasmer and wasirun). The following new flags are added:
   * `--dir=.` - this causes wasmer to set the CWD to the current directory in the filesystem (somewhat incorrectly - it only partially works with SDK 12).
   * `--mapdir=/build/openssl-${OPENSSL_VERSION}:/build/openssl-${OPENSSL_VERSION}` - this along with the flag above makes sure the tests can run properly by mapping the entire build directory from the container. I would like to simply map `/`, but this doesn't actually seem to work in current versions of wasmer.
   * `--mapdir=/dev:/dev` - this mapping is required until I can successfully set the cross compile flag (see below).
   * `--mapdir=/tmp:/tmp` - at least one test requires /tmp.
   
Additionally, every environment variable is passed to wasmer. This won't be needed once this issue is resolved: https://github.com/wasmerio/wasmer/issues/2078

### Testing

The vast majority of the test suite runs successfully, but should be audited (false positives are more likely than I would have expected). However the following test suites have been disabled for the following reasons:

* `test_errstr` - this will always fail due to linux/wasi mismatches and would be excluded if this was a legitimate cross-compile (flag set in configdata.pm).
* `test_ca` - calls to rename for missing files appear to be broken in WASI (the wrong error code is returned, see: https://github.com/wasmerio/wasmer/issues/2534).
* `test_rehash` - It looks like this could be related to the above error code issue, but also seems to point towards issues with WASI's symlink implementation (needs more investigation).
* `test_x509_store` - won't work without rehash working.

Other than the errstr test, the rest of these failures point towards issues in wasmer or the WASI SDK rather than issues in the build itself.
