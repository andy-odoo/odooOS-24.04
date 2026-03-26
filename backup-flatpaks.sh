#!/bin/bash

rm -rf ./flatpaks/.ostree

# Filter out extra-data apps — they cannot be distributed offline
apps=()
while IFS= read -r app; do
    if flatpak info --show-metadata "$app" 2>/dev/null | grep -q "^extra-data"; then
        echo "Skipping extra-data app: $app"
    else
        apps+=("$app")
    fi
done < <(flatpak list --app --columns=application | grep -v "Application ID")

if [ ${#apps[@]} -eq 0 ]; then
    echo "No apps to back up."
    exit 0
fi

flatpak create-usb --allow-partial ./flatpaks "${apps[@]}"
