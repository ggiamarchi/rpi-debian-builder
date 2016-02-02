# RPi Debian Builder

[![Build Status](https://travis-ci.org/ggiamarchi/rpi-debian-builder.svg?branch=master)](https://travis-ci.org/ggiamarchi/rpi-debian-builder)

Build your custom Debian image for RaspberryPi easily.

## Requirements

This tool runs under linux and needs some system requirements. Because it needs to be run
as root (for the chroot purspose) it is highly recommended to run it inside a virtual machine.

## Quickstart

The easiest way to run it is to use [Vagrant](https://www.vagrantup.com/) to create a fresh VM,
install requirements and then run the image build.

from the project directory

```
vagrant up
vagrant ssh
sudo su
cd /vagrant
```

Now you are inside the VM as root in the project directory, ready to run the image build. To do
so, you can do it without any customization running the command

```
./rpi-debian-builder --config config.json --modules basic
```

It uses the `basic` module which perform some elementary configuration. It is recommended to
always use it unless you really know what you are doing.

## Modules

A module is a directory containing
 * static files to deploy to the target filesystem
 * templates to generate files to the target filesystem
 * provisioning scripts


### Module directory structure

```
modules
   |-- module1
   |     |-- initialize
   |     |     |-- files
   |     |     |-- templates
   |     |     |-- scripts
   |     |
   |     |-- provision
   |     |     |-- files
   |     |     |-- templates
   |     |     |-- scripts
   |     |
   |     |-- finish
   |           |-- files
   |           |-- templates
   |           |-- scripts
   |
   |-- module2
   |     |-- ...
```

Module phases:

 * `initialize` - This phase runs before any other provisioning. It runs outside the chroot context
 * `provision` -  This phase runs after built-in provisioning. It runs in a chroot context
 * `finish` - This phase runs after the `provision` one. It runs in a chroot context

In any phase, files and templates are always relative to the root of the filesystem of the target
operating system.


### Use your own modules

To use your own module, just copy it in the `modules` directory and make reference to it on the command
line when you run the `rpi-debian-builder` command. You can reference as many module as you want (comma
separated).


## License

Everything in this repository is published under the MIT license.
