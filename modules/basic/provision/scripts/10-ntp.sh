#!/bin/bash

set -eux

apt-get install -y ntp
service ntp stop
