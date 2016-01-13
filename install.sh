#!/bin/bash

set -ex

curl -sSL https://deb.nodesource.com/setup | bash

apt-get install -y binfmt-support qemu qemu-user-static lvm2 kpartx \
                   debootstrap dosfstools apt-cacher-ng jq nodejs

npm install -g mustache
