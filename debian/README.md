# Janus Debian Package

## Overview

We use a [Dockerfile](Dockerfile) to build an ARMv7 (armhf) Debian package with precompiled Janus binaries. The resulting Debian package is stored as a Docker artifact. For example:

```bash
releases/janus_1.0.2-20220513_armhf.deb
```

## Pre-requisites

* Raspberry Pi OS (32bit) Buster
* Docker
* Git

## Build

On device, run the following commands:

```bash
# Set the Janus version.
export PKG_VERSION='1.0.2'
export PKG_BUILD_NUMBER="$(date '+%Y%m%d')"
# Enable new Docker BuildKit commands:
# https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/syntax.md
export DOCKER_BUILDKIT=1
# Build Debian package.
pushd "$(mktemp -d)" && \
  git clone https://github.com/tiny-pilot/janus-gateway.git . && \
  git checkout "v${PKG_VERSION}" && \
  docker build \
    --build-arg PKG_VERSION \
    --build-arg PKG_BUILD_NUMBER \
    --target=artifact \
    --output "type=local,dest=$(pwd)/releases/" \
    --file debian/Dockerfile \
    .
```

## Install

On device, run the following command:

```bash
# Install dependencies.
sudo apt-get install --yes \
  libconfig9 \
  libjansson4
# Install Janus.
sudo dpkg --install \
  "releases/janus_${PKG_VERSION}-${PKG_BUILD_NUMBER}_armhf.deb"
```

You can confirm that the Janus systemd service is running, by executing the following command:

```bash
sudo systemctl status janus.service
```

## Uninstall

On device, run the following command:

```bash
sudo dpkg --purge janus
```
