#!/bin/bash

rm -rf ./flatpaks/.ostree

for f in `flatpak list --app --columns=application | grep -v "Application ID"` ; do flatpak create-usb ./flatpaks $f ; done
