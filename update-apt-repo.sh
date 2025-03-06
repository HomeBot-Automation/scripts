#!/bin/bash

set -e

# Check arguments
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <username> <server>"
    exit 1
fi

USERNAME=$1
SERVER=$2

# Get script directory
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

# Get Debian codename
CODENAME=$(lsb_release -cs)

# Create a temporary sources.list in the script's directory
TMP_SOURCES="$SCRIPT_DIR/custom_sources.list"

cat > "$TMP_SOURCES" <<EOF
deb http://deb.debian.org/debian $CODENAME main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $CODENAME-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $CODENAME-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $CODENAME-backports main contrib non-free non-free-firmware
EOF

echo "Using temporary sources.list located at: $TMP_SOURCES"

# Update package lists using only the temporary sources
sudo apt update -o Dir::Etc::sourcelist="$TMP_SOURCES"

# Simulate a full-upgrade to get all packages (including dependencies)
echo "Fetching list of all packages (including dependencies)..."
UPGRADE_PACKAGES=$(sudo apt --dry-run -o Dir::Etc::sourcelist="$TMP_SOURCES" full-upgrade | awk '/^Inst / {print $2}')

if [[ -z "$UPGRADE_PACKAGES" ]]; then
    echo "No packages need upgrading."
    rm -f "$TMP_SOURCES"
    exit 0
fi

# Create a clean download directory
LOCAL_PKG_DIR="$HOME/downloaded_packages"
rm -rf "$LOCAL_PKG_DIR"
mkdir -p "$LOCAL_PKG_DIR"

# Change to the download directory
pushd "$LOCAL_PKG_DIR" > /dev/null

# Download each package including dependencies
echo "Downloading packages and their dependencies..."
for pkg in $UPGRADE_PACKAGES; do
    apt download -o Dir::Etc::sourcelist="$TMP_SOURCES" "$pkg"
done

# Fix ownership so normal user can access the files
sudo chown -R "$USER:$USER" "$LOCAL_PKG_DIR"

# Return to the original directory
popd > /dev/null

echo "Packages (including dependencies) downloaded to $LOCAL_PKG_DIR"

# Ensure the remote server has a clean directory setup
echo "Preparing the destination directory on the remote server..."
ssh "$USERNAME@$SERVER" <<EOF
    if [ -d "~/downloaded_packages_old" ]; then
        rm -rf ~/downloaded_packages_old
        echo "Removed old downloaded_packages_old directory."
    fi
    if [ -d "~/downloaded_packages" ]; then
        rm -rf ~/downloaded_packages
        echo "Removed existing downloaded_packages directory."
    fi
    mkdir -p ~/downloaded_packages
    echo "Created new downloaded_packages directory."
EOF

# Transfer package files via SCP
echo "Transferring package files to the remote server..."
scp "$LOCAL_PKG_DIR"/*.deb "$USERNAME@$SERVER:~/downloaded_packages/"

echo "All package files and dependencies transferred to $USERNAME@$SERVER:~/downloaded_packages/"

# Delete local downloaded packages directory after transfer
rm -rf "$LOCAL_PKG_DIR"
echo "Deleted local downloaded_packages directory."

# Check if update-mirror.sh exists on the remote server and remove it if found
echo "Checking for update-mirror.sh on the remote server..."
ssh "$USERNAME@$SERVER" <<EOF
    if [ -f "~/update-mirror.sh" ]; then
        rm ~/update-mirror.sh
        echo "Removed existing update-mirror.sh."
    fi
EOF

# Copy update-mirror.sh to the remote server
echo "Copying update-mirror.sh to the remote server..."
scp "$SCRIPT_DIR/update-mirror.sh" "$USERNAME@$SERVER:~/"

# Execute update-mirror.sh as sudo on the remote server
echo "Executing update-mirror.sh as sudo on the remote server..."
ssh -t "$USERNAME@$SERVER" "sudo bash ~/update-mirror.sh"

# Remove the temporary sources file
rm -f "$TMP_SOURCES"
echo "Deleted temporary sources.list."

echo "Script completed successfully."

