#!/bin/bash

# Exit on error
set -e

# Constants
UPSTREAM_URL="https://version.home-assistant.io/stable.json"
MACHINE="raspberrypi4-64"
ARCH="aarch64"
REGISTRY="ha.homebotautomation.com"

# Images map for components
declare -A COMPONENTS=(
    ["core"]="homeassistant[\"$MACHINE\"]"
    ["cli"]="cli"
    ["audio"]="audio"
    ["dns"]="dns"
    ["observer"]="observer"
    ["multicast"]="multicast"
)

# Check if paths are provided
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <path-to-supervisor-repo> <path-to-version-repo> <username> <domain>"
    exit 1
fi

SUPERVISOR_REPO=$(realpath "$1")
VERSION_REPO=$(realpath "$2")
USERNAME=$3
DOMAIN=$4

# Verify paths
if [ ! -d "$SUPERVISOR_REPO" ]; then
    echo "Error: Supervisor repository directory '$SUPERVISOR_REPO' does not exist."
    exit 1
fi

if [ ! -d "$VERSION_REPO" ]; then
    echo "Error: Version repository directory '$VERSION_REPO' does not exist."
    exit 1
fi

# Authenticate with the Docker registry
echo "Authenticating with Docker registry: $REGISTRY..."
if ! docker login "$REGISTRY"; then
    echo "Error: Authentication failed for registry $REGISTRY."
    exit 1
fi

# Get the latest tag from the supervisor repo
echo "Fetching latest tag from the supervisor repository..."
cd "$SUPERVISOR_REPO"
git fetch --tags
SUPERVISOR_VERSION=$(git describe --tags $(git rev-list --tags --max-count=1))

if [ -z "$SUPERVISOR_VERSION" ]; then
    echo "Error: No tags found in the supervisor repository."
    exit 1
fi

echo "Latest supervisor version: $SUPERVISOR_VERSION"

# Fetch upstream JSON data
echo "Fetching upstream Home Assistant stable JSON..."
UPSTREAM_JSON=$(curl -s "$UPSTREAM_URL")
if [ -z "$UPSTREAM_JSON" ]; then
    echo "Error: Failed to fetch data from $UPSTREAM_URL"
    exit 1
fi

# Navigate to the version repository
echo "Navigating to the version repository..."
cd "$VERSION_REPO"

# Update stable.json
STABLE_FILE="stable.json"
if [ ! -f "$STABLE_FILE" ]; then
    echo "Error: $STABLE_FILE not found in the version repository."
    exit 1
fi

echo "Updating $STABLE_FILE with the latest versions..."

# Backup the original stable.json for safety
cp "$STABLE_FILE" "${STABLE_FILE}.backup"

# Extract core version for raspberrypi4-64
CORE_VERSION=$(jq -r ".homeassistant[\"$MACHINE\"]" <<< "$UPSTREAM_JSON")

# Use jq to update stable.json
jq --arg supervisor "$SUPERVISOR_VERSION" \
   --arg core_version "$CORE_VERSION" \
   --arg cli_version "$(jq -r '.cli' <<< "$UPSTREAM_JSON")" \
   --arg audio_version "$(jq -r '.audio' <<< "$UPSTREAM_JSON")" \
   --arg dns_version "$(jq -r '.dns' <<< "$UPSTREAM_JSON")" \
   --arg observer_version "$(jq -r '.observer' <<< "$UPSTREAM_JSON")" \
   --arg multicast_version "$(jq -r '.multicast' <<< "$UPSTREAM_JSON")" \
   '
   .supervisor = $supervisor
   | .homeassistant["raspberrypi4-64"] = $core_version
   | .cli = $cli_version
   | .audio = $audio_version
   | .dns = $dns_version
   | .observer = $observer_version
   | .multicast = $multicast_version
   ' "$STABLE_FILE" > "${STABLE_FILE}.tmp" || {
    echo "Error: Failed to update $STABLE_FILE. Restoring from backup."
    mv "${STABLE_FILE}.backup" "$STABLE_FILE"
    exit 1
}

# Overwrite the stable.json file with the updated version
mv "${STABLE_FILE}.tmp" "$STABLE_FILE"
rm -f "${STABLE_FILE}.backup"

echo "Updated $STABLE_FILE successfully!"

# Check if images need to be pulled, tagged, and pushed
for COMPONENT in "${!COMPONENTS[@]}"; do
    UPSTREAM_VERSION=$(jq -r ".${COMPONENTS[$COMPONENT]}" <<<"$UPSTREAM_JSON")

    # Handle special case for core (raspberrypi4-64-homeassistant)
    if [[ "$COMPONENT" == "core" ]]; then
        IMAGE_SOURCE="ghcr.io/home-assistant/$MACHINE-homeassistant:$UPSTREAM_VERSION"
        IMAGE_TARGET="$REGISTRY/homebot/$MACHINE-homeassistant:$UPSTREAM_VERSION"
    else
        IMAGE_SOURCE="ghcr.io/home-assistant/$ARCH-hassio-$COMPONENT:$UPSTREAM_VERSION"
        IMAGE_TARGET="$REGISTRY/homebot/$ARCH-hassio-$COMPONENT:$UPSTREAM_VERSION"
    fi

    echo "Attempting to pull $IMAGE_TARGET from the registry..."
    if docker pull "$IMAGE_TARGET"; then
        echo "$IMAGE_TARGET already exists in the registry. Cleaning up local image."
        docker rmi "$IMAGE_TARGET"
        continue
    else
        echo "$IMAGE_TARGET does not exist in the registry. Proceeding to build and push..."
    fi

    # Pull the source image
    echo "Pulling source image: $IMAGE_SOURCE"
    docker pull "$IMAGE_SOURCE"

    # Tag and push the image
    echo "Tagging and pushing image: $IMAGE_TARGET"
    docker tag "$IMAGE_SOURCE" "$IMAGE_TARGET"
    docker push "$IMAGE_TARGET"

    # Remove local images to save space
    echo "Cleaning up local images..."
    docker rmi "$IMAGE_SOURCE"
    docker rmi "$IMAGE_TARGET"
done

# Commit and push changes to the version repository
echo "Checking for changes to commit..."
if ! git diff --quiet; then
    echo "Changes detected. Committing and pushing changes..."
    git add "$STABLE_FILE"
    git commit -m "Update stable.json with supervisor $SUPERVISOR_VERSION and latest components"
    git push
else
    echo "No changes detected. Skipping commit and push."
fi

echo "Updating version on website"
ssh -t $USERNAME@$DOMAIN sudo ./update_version.sh

echo "Process complete."
