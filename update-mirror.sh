#!/bin/bash

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Define the base directory for the main Debian repository
BASEDIR="/var/spool/apt-mirror/mirror/debian"

# Define distributions, components, and architectures
MAIN_DISTRIBUTIONS="bookworm"
COMPONENTS="main"
ARCHITECTURES="arm64 armhf"  # Added armhf to the list

# Define the list of directories to create and check for packages
DIR_LIST=("0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "a" "b" "c" "d" "e" "f" "g" "h" "i" "j" "k" "lib0" "lib1" "lib2" "lib3" "lib4" "lib5" "lib6" "lib7" "lib8" "lib9" "liba" "libb" "libc" "libd" "libe" "libf" "libg" "libh" "libi" "libj" "libk" "libl" "libm" "libn" "libo" "libp" "libq" "libr" "libs" "libt" "libu" "libv" "libw" "libx" "liby" "libz" "l" "m" "n" "o" "p" "q" "r" "s" "t" "u" "v" "w" "x" "y" "z")

DOWNLOADED_PACKAGES="$SCRIPT_DIR/downloaded_packages"

# Directory for storing old packages
OLD_PACKAGE_DIR="$SCRIPT_DIR/old_packages"
mkdir -p "$OLD_PACKAGE_DIR"

# File to log package replacements
PACKAGE_LOG="$OLD_PACKAGE_DIR/package_replacements.log"
> "$PACKAGE_LOG"

# Function to organize packages into subdirectories
organize_packages() {
    local distro=$1
    local component=$2

    # Create pool/$distro/$component directory if it does not exist
    mkdir -p "$BASEDIR/pool/$distro/$component"

    # Move .deb packages into the appropriate subdirectories
    for dir in "${DIR_LIST[@]}"; do
        # Check if there are .deb files starting with the directory prefix
        deb_files=$(find "$DOWNLOADED_PACKAGES" -maxdepth 1 -type f -name "${dir}*.deb")
        
        if [[ -n "$deb_files" ]]; then
            # Only create the directory if there are matching .deb files
            mkdir -p "$BASEDIR/pool/$distro/$component/$dir"
            
            # Process each .deb file
            for package in $deb_files; do
                package_name=$(basename "$package" | cut -d'_' -f1)
                existing_package=$(find "$BASEDIR/pool/$distro/$component/$dir" -type f -name "${package_name}_*.deb")

                if [[ -n "$existing_package" ]]; then
                    mv "$existing_package" "$OLD_PACKAGE_DIR"
                    echo "Replaced: $existing_package with $package" >> "$PACKAGE_LOG"
                fi

                mv "$package" "$BASEDIR/pool/$distro/$component/$dir/"
            done
        fi
    done
}

# Function to scan packages and generate Packages files
scan_packages() {
    local distro=$1
    local component=$2
    local architecture=$3

    local poolpath="pool/$distro/$component"
    # Output directory for the Packages files
    local outpath="dists/$distro/$component/binary-$architecture"

    echo "Processing $distro / $component / $architecture"

    # Change to the basepath
    cd $BASEDIR || { echo "Failed to change directory to $BASEDIR"; exit 1; }

    # Create the directory if it does not exist
    mkdir -p $outpath

    # Generate Packages file, specifying poolpath relative to the current directory
    dpkg-scanpackages $poolpath /dev/null > $outpath/Packages 2>/dev/null

    # Compress the Packages file with gzip and xz, only if the Packages file exists and is not empty
    if [[ -s $outpath/Packages ]]; then
        gzip -9c $outpath/Packages > $outpath/Packages.gz
        xz -c9 $outpath/Packages > $outpath/Packages.xz
    fi
}

# Generate Release files with apt-ftparchive
generate_release() {
    local distro=$1

    # Change to the basepath
    cd $BASEDIR || { echo "Failed to change directory to $BASEDIR"; exit 1; }

    apt-ftparchive -o "APT::FTPArchive::Release::Origin=HomeBotAutomation" \
                   -o "APT::FTPArchive::Release::Label=HomeBotAutomation" \
                   -o "APT::FTPArchive::Release::Suite=$distro" \
                   -o "APT::FTPArchive::Release::Codename=$distro" \
                   -o "APT::FTPArchive::Release::Architectures=$ARCHITECTURES" \
                   -o "APT::FTPArchive::Release::Components=$COMPONENTS" \
                   release dists/$distro > dists/$distro/Release

    # Sign the Release file if needed
    gpg --verbose --default-key 'jacob.k.tm@gmail.com' --clearsign --output dists/$distro/InRelease dists/$distro/Release
    gpg --verbose --default-key 'jacob.k.tm@gmail.com' --detach-sign --output dists/$distro/Release.gpg dists/$distro/Release
}

# Function to update repository
update_repository() {
    for distro in $MAIN_DISTRIBUTIONS; do
        # Organize packages before updating repository metadata
        for component in $COMPONENTS; do
            organize_packages $distro $component
            for architecture in $ARCHITECTURES; do
                scan_packages $distro $component $architecture
            done
        done
        generate_release $distro
    done

    echo "Repository update complete."
}

# Navigate to the base directory
if [ ! -e "$BASEDIR" ]; then
    mkdir -p "$BASEDIR"
fi
cd $BASEDIR || { echo "Failed to change directory to $BASEDIR"; exit 1; }

# Update the repository
update_repository

