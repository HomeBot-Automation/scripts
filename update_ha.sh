#!/bin/bash

# exit on any error
set -e

# Check for correct number of arguments
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <supervisor-repo> <version-repo> <addon-repo> <username> <domain>"
    exit 1
fi

./sync_docker_images.sh $1 $2 $4 $5
./sync_and_tag.sh $1 $3
./build_supervisor.sh $1
