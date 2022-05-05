FROM debian:buster-20220418-slim AS build

ARG PKG_NAME="janus-gateway"
ARG PKG_VERSION="0.0.0"
ARG PKG_BUILD_NUMBER="1"
ARG PKG_ARCH="armhf"
ARG PKG_ID="${PKG_NAME}-${PKG_VERSION}-${PKG_BUILD_NUMBER}-${PKG_ARCH}"
ARG PKG_DIR="/releases/${PKG_ID}"
ARG INSTALL_DIR="${PKG_DIR}/opt/janus"

RUN set -x && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      dpkg-dev

RUN mkdir -p "${PKG_DIR}"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libmicrohttpd-dev \
    libjansson-dev \
    libssl-dev \
    libsofia-sip-ua-dev \
    libglib2.0-dev \
    libopus-dev \
    libogg-dev \
    libcurl4-openssl-dev \
    liblua5.3-dev \
    libconfig-dev \
    pkg-config \
    gengetopt \
    libtool \
    automake \
    cmake \
    make \
    wget \
    git \
    build-essential \
    ninja-build \
    python3 \
    python3-pip

RUN pip3 install meson

# libince is recommended to be installed from source because the version installed via apt is too low
RUN git clone https://gitlab.freedesktop.org/libnice/libnice && \
    cd libnice && \
    meson --prefix=/usr build && \
    ninja -C build && \
    ninja -C build install

RUN wget https://github.com/cisco/libsrtp/archive/v2.2.0.tar.gz && \
    tar xfv v2.2.0.tar.gz && \
    cd libsrtp-2.2.0 && \
    ./configure --prefix=/usr --enable-openssl && \
    make shared_library && \
    make install

RUN git clone https://libwebsockets.org/repo/libwebsockets && \
    cd libwebsockets && \
    # If you want the stable version of libwebsockets, uncomment the next line
    # git checkout v3.2-stable && \
    mkdir build && \
    cd build && \
    # See https://github.com/meetecho/janus-gateway/issues/732 re: LWS_MAX_SMP
    # See https://github.com/meetecho/janus-gateway/issues/2476 re: LWS_WITHOUT_EXTENSIONS
    cmake -DLWS_MAX_SMP=1 -DLWS_WITHOUT_EXTENSIONS=0 -DCMAKE_INSTALL_PREFIX:PATH=/usr -DCMAKE_C_FLAGS="-fpic" .. && \
    make && \
    make install

RUN git clone https://github.com/meetecho/janus-gateway.git && \
    cd janus-gateway && \
    sh autogen.sh && \
    # we didn't install the dependencies (nor are they needed) for the disabled parts
    ./configure --prefix="${INSTALL_DIR}" --disable-data-channels --disable-rabbitmq --disable-mqtt && \
    make && \
    make install

RUN cat > "${INSTALL_DIR}/etc/janus/janus.transport.websockets.jcfg" <<EOF
general: {
    ws = true
	ws_ip = "127.0.0.1"
    ws_port = 8002
}
EOF

RUN mkdir -p "${PKG_DIR}/DEBIAN"

WORKDIR "${PKG_DIR}/DEBIAN"

RUN echo "Package: ${PKG_NAME}" >> control && \
    echo "Version: ${PKG_VERSION}" >> control && \
    echo "Maintainer: TinyPilot Support <support@tinypilotkvm.com>" >> control && \
    `# TODO: Add other dependencies` && \
    echo "Depends: libc6" >> control && \
    echo "Architecture: ${PKG_ARCH}" >> control && \
    echo "Homepage: https://janus.conf.meetecho.com/" >> control && \
    echo "Description: An open source, general purpose, WebRTC server" >> control

RUN cat > preinst <<EOF
#!/bin/bash
rm -rf /opt/janus
EOF

RUN chmod 0555 preinst

RUN dpkg --build "${PKG_DIR}"

FROM scratch as artifact

COPY --from=build "/releases/*.deb" ./
