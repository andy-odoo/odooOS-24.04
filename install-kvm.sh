#!/bin/bash

#Install KVM

sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager -y

#Copy VM

sudo cp ./ubuntu24.04LTS.qcow2 /var/lib/libvirt/images
