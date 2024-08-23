#!/bin/bash

# Create a directory to store downloaded packages
DOWNLOAD_DIR="downloaded_packages"
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

# Getting a list of all installed packages and their versions
dpkg -l | grep '^ii' | awk '{print $2 "=" $3}' | sed 's/:\(amd64\|i386\|armhf\|arm64\)//' > installed_packages_list.txt

# Reading each package from the list and downloading it
while IFS= read -r package; do
    echo "Downloading $package..."
    apt download "$package" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "$package downloaded successfully."
    else
        echo "Failed to download $package. It may be a virtual package or provided by a different source."
    fi
done < installed_packages_list.txt

echo "All packages processed. Downloads are in $DOWNLOAD_DIR."
