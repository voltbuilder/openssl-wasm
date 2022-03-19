FROM artlogical/wasienv:latest

# install some deps specifically for building openssl
RUN apt-get update && apt-get install -y --no-install-recommends build-essential libfindbin-libs-perl

ENV OPENSSL_VERSION="1.1.1n"

WORKDIR /build

COPY build.sh .
COPY openssl-${OPENSSL_VERSION}.patch  .

ENTRYPOINT ["/build/build.sh"]
