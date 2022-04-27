FROM debian:bullseye-20220328-slim AS build

ARG PKG_NAME="janus-gateway"
ARG PKG_VERSION="0.0.0"
ARG PKG_BUILD_NUMBER="1"
ARG PKG_ARCH="armhf"
ARG PKG_ID="${PKG_NAME}-${PKG_VERSION}-${PKG_BUILD_NUMBER}-${PKG_ARCH}"
RUN set -x && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
      dpkg-dev

# TODO: Actually build Janus binaries and place them in the correct places.

WORKDIR /app

RUN mkdir -p "/releases/${PKG_ID}"

WORKDIR "/releases/${PKG_ID}"

RUN mkdir -p DEBIAN

WORKDIR "/releases/${PKG_ID}/DEBIAN"

RUN echo "Package: ${PKG_NAME}" >> control && \
    echo "Version: ${PKG_VERSION}" >> control && \
    echo "Maintainer: TinyPilot Support <support@tinypilotkvm.com>" >> control && \
    `# TODO: Add other dependencies` && \
    echo "Depends: " >> control && \
    echo "Architecture: ${PKG_ARCH}" >> control && \
    echo "Homepage: https://janus.conf.meetecho.com/" >> control && \
    echo "Description: An open source, general purpose, WebRTC server" >> control

RUN dpkg --build "/releases/${PKG_ID}"

FROM scratch as artifact

COPY --from=build "/releases/*.deb" ./
