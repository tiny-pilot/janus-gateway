FROM debian:buster-20220418-slim AS build

ARG PKG_NAME="janus"
ARG PKG_VERSION="0.0.0"
ARG PKG_BUILD_NUMBER="1"
ARG PKG_ARCH="armhf"
ARG PKG_ID="${PKG_NAME}_${PKG_VERSION}-${PKG_BUILD_NUMBER}_${PKG_ARCH}"
ARG PKG_DIR="/releases/${PKG_ID}"
ARG INSTALL_DIR="/usr"

RUN set -x && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      dpkg-dev

RUN apt-get install -y --no-install-recommends \
    git \
    wget \
    libjansson-dev \
    libconfig-dev \
    libssl-dev \
    cmake \
    automake \
    libtool \
    libglib2.0-dev \
    pkg-config \
    gengetopt \
    python3-pip \
    ninja-build

RUN pip3 install meson

# libince is recommended to be installed from source because the version
# installed via apt is too low.
RUN git clone https://gitlab.freedesktop.org/libnice/libnice \
        --branch 0.1.18 \
        --single-branch && \
    cd libnice && \
    meson --prefix=/usr build && \
    ninja -C build && \
    ninja -C build install

RUN wget https://github.com/cisco/libsrtp/archive/v2.2.0.tar.gz && \
    tar xfv v2.2.0.tar.gz && \
    cd libsrtp-2.2.0 && \
    ./configure --prefix=/usr \
        --enable-openssl && \
    make shared_library && \
    make install

RUN git clone https://libwebsockets.org/repo/libwebsockets \
        --branch v3.2-stable \
        --single-branch && \
    cd libwebsockets && \
    mkdir build && \
    cd build && \
    # See https://github.com/meetecho/janus-gateway/issues/732 re: LWS_MAX_SMP
    # See https://github.com/meetecho/janus-gateway/issues/2476 re: LWS_WITHOUT_EXTENSIONS
    cmake -DLWS_MAX_SMP=1 -DLWS_WITHOUT_EXTENSIONS=0 \
        -DCMAKE_INSTALL_PREFIX:PATH=/usr -DCMAKE_C_FLAGS="-fpic" .. && \
    make && \
    make install

RUN git clone https://github.com/meetecho/janus-gateway.git \
        --branch v1.0.0 \
        --single-branch && \
    cd janus-gateway && \
    sh autogen.sh && \
    ./configure --prefix=/usr \
        --disable-all-plugins \
        --disable-all-transports \
        --disable-all-handlers \
        --disable-all-loggers \
        --enable-websockets && \
    make && \
    make install

# Allow Janus C header files to be included when compiling third-party plugins.
# Issue: https://github.com/tiny-pilot/ansible-role-tinypilot/issues/192
RUN sed -i -e 's|^#include "refcount.h"$|#include "../refcount.h"|g' \
    "${INSTALL_DIR}/include/janus/plugins/plugin.h"

# Ensure Janus default library directories exist.
RUN mkdir --parents "${INSTALL_DIR}/lib/janus/plugins" \
    "${INSTALL_DIR}/lib/janus/transports" \
    "${INSTALL_DIR}/lib/janus/loggers"

# Use Janus sample config.
RUN mv "${INSTALL_DIR}/etc/janus/janus.jcfg.sample" \
        "${INSTALL_DIR}/etc/janus/janus.jcfg" && \
    mv "${INSTALL_DIR}/etc/janus/janus.transport.websockets.jcfg.sample" \
        "${INSTALL_DIR}/etc/janus/janus.transport.websockets.jcfg"

# Overwrite Janus WebSocket config.
RUN cat > "${INSTALL_DIR}/etc/janus/janus.transport.websockets.jcfg" <<EOF
general: {
    ws = true
    ws_ip = "127.0.0.1"
    ws_port = 8002
}
EOF

RUN cat > "/lib/systemd/system/janus.service" <<EOF
[Unit]
Description=Janus WebRTC gateway
After=network.target
Documentation=https://janus.conf.meetecho.com/docs/index.html

[Service]
Type=forking
ExecStart=/usr/bin/janus --disable-colors --daemon --log-stdout
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

RUN mkdir --parents "${PKG_DIR}"

# Add Janus files to the Debian package.
RUN cp --parents --recursive "${INSTALL_DIR}/etc/janus" \
    "${INSTALL_DIR}/bin/janus" \
    "${INSTALL_DIR}/bin/janus-cfgconv" \
    "${INSTALL_DIR}/lib/janus" \
    "${INSTALL_DIR}/include/janus" \
    "${INSTALL_DIR}/share/janus" \
    "${INSTALL_DIR}/share/doc/janus-gateway" \
    "${INSTALL_DIR}/share/man/man1/janus.1" \
    "${INSTALL_DIR}/share/man/man1/janus-cfgconv.1" \
    /lib/systemd/system/janus.service \
    "${PKG_DIR}/"

# Add Janus compiled shared library dependencies to the Debian package.
RUN cp --parents --no-dereference /usr/lib/arm-linux-gnueabihf/libnice.so* \
    /usr/lib/libsrtp2.so* \
    /usr/lib/libwebsockets.so* \
    "${PKG_DIR}/"

RUN mkdir "${PKG_DIR}/DEBIAN"

WORKDIR "${PKG_DIR}/DEBIAN"

RUN cat > control <<EOF
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Maintainer: TinyPilot Support <support@tinypilotkvm.com>
Depends: libconfig9, libglib2.0-0, libjansson4, libssl1.1, libc6, libsystemd0
Conflicts: libnice10, libsrtp2-1, libwebsockets16
Architecture: ${PKG_ARCH}
Homepage: https://janus.conf.meetecho.com/
Description: An open source, general purpose, WebRTC server
EOF

RUN cat > triggers <<EOF
# Reindex shared libraries.
activate-noawait ldconfig
EOF

RUN cat > preinst <<EOF
#!/bin/bash
systemctl disable --now janus.service > /dev/null 2>&1 || true
EOF
RUN chmod 0555 preinst

RUN cat > postinst <<EOF
#!/bin/bash
systemctl enable --now janus.service > /dev/null 2>&1 || true
EOF
RUN chmod 0555 postinst

RUN cat > postrm <<EOF
#!/bin/bash
systemctl disable --now janus.service > /dev/null 2>&1 || true
EOF
RUN chmod 0555 postrm

RUN dpkg --build "${PKG_DIR}"

FROM scratch as artifact

COPY --from=build "/releases/*.deb" ./
