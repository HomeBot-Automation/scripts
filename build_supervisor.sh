#!/bin/bash

# Exit on error
set -e

# Check if a path to the repo is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-repo>"
    exit 1
fi

# Navigate to the specified repository path
REPO_PATH=$(realpath "$1")
if [ ! -d "$REPO_PATH" ]; then
    echo "Error: Directory '$REPO_PATH' does not exist."
    exit 1
fi

cd "$REPO_PATH"

# Verify the path is a Git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Error: '$REPO_PATH' is not a git repository."
    exit 1
fi

# Fetch the latest tags from the repository
echo "Fetching tags from the repository..."
git fetch --tags

# Determine the latest tag
LATEST_TAG=$(git describe --tags $(git rev-list --tags --max-count=1))
if [ -z "$LATEST_TAG" ]; then
    echo "Error: No tags found in the repository."
    exit 1
fi

echo "Latest tag found: $LATEST_TAG"

# Checkout the latest tag
echo "Checking out the latest tag..."
git checkout "$LATEST_TAG"

# Paths to files to modify
CONST_FILE="supervisor/const.py"
SETUP_FILE="setup.py"

# Back up the original files
echo "Backing up original files..."
cp "$CONST_FILE" "$CONST_FILE.bak"
cp "$SETUP_FILE" "$SETUP_FILE.bak"

# Update supervisor/const.py
echo "Updating $CONST_FILE with the latest tag..."
sed -i "s/^SUPERVISOR_VERSION = .*/SUPERVISOR_VERSION = \"$LATEST_TAG\"/" "$CONST_FILE"

# Update setup.py
echo "Updating $SETUP_FILE with the latest tag..."
sed -i "s/return \"99.9.9dev\"/return \"$LATEST_TAG\"/" "$SETUP_FILE"

# Build the Docker container
echo "Building the Docker container..."
IMAGE_TAG="ha.homebotautomation.com/homebot/aarch64-hassio-supervisor:$LATEST_TAG"
docker buildx build \
    --platform linux/arm64 \
    --build-arg SUPERVISOR_VERSION="$LATEST_TAG" \
    --build-arg BUILD_FROM="ghcr.io/home-assistant/aarch64-base-python:3.12-alpine3.20" \
    -t "$IMAGE_TAG" \
    --load .

# Push the Docker container to the registry
echo "Pushing the Docker container to the registry..."
docker push "$IMAGE_TAG"

# Revert the changes
echo "Reverting changes to the original files..."
mv "$CONST_FILE.bak" "$CONST_FILE"
mv "$SETUP_FILE.bak" "$SETUP_FILE"

# Switch back to the main branch (or default branch)
echo "Switching back to the main branch..."
git checkout main

echo "Docker container built, pushed successfully, and changes reverted!"

