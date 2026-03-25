#!/bin/bash

rm -rf ./flatpaks/.ostree

mapfile -t apps < <(flatpak list --app --columns=application | grep -v "Application ID")
flatpak create-usb ./flatpaks "${apps[@]}"
