#!/bin/bash

# Create a directory to work in
WORKING_DIR="package_check"
mkdir -p "$WORKING_DIR"
cd "$WORKING_DIR"

# Getting a list of all installed packages with their versions
dpkg -l | grep '^ii' | awk '{print $2 "=" $3}' | sed 's/:\(amd64\|i386\|armhf\|arm64\)//' > installed_packages_list.txt

# File to store packages that failed to download
FAILED_DOWNLOADS="failed_packages_list.txt"
> "$FAILED_DOWNLOADS" # Clear the file before starting

# Function to check if a package can be downloaded
check_package_download() {
    # Using apt-get download with --print-uris to simulate the download and capture the output
    # The output will be empty if the package cannot be downloaded
    if ! apt-get download --print-uris "$1" &> /dev/null; then
        # If the download command fails, append the package to the failed list
        echo "$1" >> "$FAILED_DOWNLOADS"
        echo "Failed to download $1."
    else
        echo "$1 is available for download."
    fi
}

# Reading each package from the list and checking if it can be downloaded
while IFS= read -r package; do
    check_package_download "$package"
done < installed_packages_list.txt

echo "All packages processed. Packages that failed to download are listed in $FAILED_DOWNLOADS."
