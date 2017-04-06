#!/bin/bash

set -ex

curl -sL https://deb.nodesource.com/setup_4.x | sudo -E bash -

sudo apt-get install -y binfmt-support qemu qemu-user-static lvm2 kpartx \
                   debootstrap dosfstools apt-cacher-ng jq nodejs build-essential

sudo npm install -g mustache
