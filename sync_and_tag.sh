#!/bin/bash

# Exit on any error
set -e

# Check if a paths are provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <supervisor-repo> <addon-repo>"
    exit 1
fi

# Navigate to the specified repository path
REPO_PATH=$(realpath "$1")
if [ ! -d "$REPO_PATH" ]; then
    echo "Error: Directory '$REPO_PATH' does not exist."
    exit 1
fi

ADDON_PATH=$(realpath "$2")
if [ ! -d "$ADDON_PATH" ]; then
    echo "Error: Directory '$ADDON_PATH' does not exist."
    exit 1
fi

cd "$REPO_PATH"

# Verify the path is a Git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Error: '$REPO_PATH' is not a git repository."
    exit 1
fi

# Fetch updates and tags from upstream
echo "Fetching updates from upstream..."
git fetch upstream

# Sync `main` branch
echo "Switching to main branch..."
git checkout main

echo "Rebasing main onto upstream/main to preserve changes..."
if ! git rebase upstream/main; then
    echo "Conflict detected during rebase. Resolving interactively..."
    while true; do
        if git diff --name-only --diff-filter=U | grep .; then
            echo "Conflicts detected. Resolving interactively..."
            CONFLICT_FILES=$(git diff --name-only --diff-filter=U)
            for FILE in $CONFLICT_FILES; do
                echo "Opening file for conflict resolution: $FILE"
                vim "$FILE"  # Open file in vim
                git add "$FILE"
            done
            git rebase --continue || true
        else
            break
        fi
    done
fi

echo "Rebase complete. Pushing updated main branch to origin..."
git push origin main

# Fetch tags from upstream
echo "Fetching tags from upstream..."
EXISTING_TAGS=$(git tag) # Get existing tags before fetch
git fetch --tags --force upstream
NEW_TAGS=$(comm -13 <(echo "$EXISTING_TAGS" | sort) <(git tag | sort)) # Get newly fetched tags

echo "Newly fetched tags: $NEW_TAGS"
if [ -z "$NEW_TAGS" ]; then
    echo "No new tags to push. Skipping."
else
    echo "Pushing new tags to origin..."
    for TAG in $NEW_TAGS; do
        echo "Pushing tag: $TAG"
        git push origin --force "$TAG"
    done
fi

# Get the latest tag from upstream
LATEST_TAG=$(git describe --tags $(git rev-list --tags --max-count=1))
if [ -z "$LATEST_TAG" ]; then
    echo "Error: No tags found in the upstream repository."
    exit 1
fi
echo "Latest tag found: $LATEST_TAG"

# Check for unique commits in main not included in the latest tag
echo "Checking for unique commits in main not included in the latest tag..."
UNIQUE_COMMITS=$(git log --oneline origin/main ^"$LATEST_TAG" | awk '{print $1}')
if [ -z "$UNIQUE_COMMITS" ]; then
    echo "No unique commits found. Exiting."
    exit 0
fi

echo "Unique commits found: $UNIQUE_COMMITS"

# Create a new branch for cherry-picking unique commits
NEW_BRANCH="updated-with-latest-tag"
echo "Creating a new branch ($NEW_BRANCH) based on $LATEST_TAG..."
git checkout -b "$NEW_BRANCH" "$LATEST_TAG"

# Cherry-pick unique commits onto the new branch
for COMMIT in $UNIQUE_COMMITS; do
    echo "Cherry-picking commit: $COMMIT"
    if ! git cherry-pick "$COMMIT"; then
        echo "Conflict detected. Resolving interactively..."
        while true; do
            if git diff --name-only --diff-filter=U | grep .; then
                echo "Conflicts detected. Resolving interactively..."
                CONFLICT_FILES=$(git diff --name-only --diff-filter=U)
                for FILE in $CONFLICT_FILES; do
                    echo "Opening file for conflict resolution: $FILE"
                    vim "$FILE"  # Open file in vim
                    git add "$FILE"
                done
                git cherry-pick --continue || true
            else
                break
            fi
        done
    fi
done

# Delete the existing tag locally
echo "Deleting the existing tag locally: $LATEST_TAG"
git tag -d "$LATEST_TAG"

# Recreate the tag with updated commits
echo "Recreating the tag with updated commits: $LATEST_TAG"
git tag -a "$LATEST_TAG" -m "Updated $LATEST_TAG with unique commits"

# Push the updated tag to origin
echo "Pushing updated tag to origin..."
git push origin --force "$LATEST_TAG"

# Switch back to the main branch
echo "Switching back to main branch..."
git checkout main

# Delete the temporary branch
echo "Deleting temporary branch ($NEW_BRANCH)..."
git branch -D "$NEW_BRANCH"

echo "Process completed successfully! Main synced, tags updated, and unique commits added to the latest tag."

echo "Updating addons"

cd "$ADDON_PATH"

# Verify the path is a Git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Error: '$ADDON_PATH' is not a git repository."
    exit 1
fi

# Fetch updates and tags from upstream
echo "Fetching updates from upstream..."
git fetch upstream

# Sync `master` branch
echo "Switching to master branch..."
git checkout master

echo "Rebasing main onto upstream/master to preserve changes..."
if ! git rebase upstream/master; then
    echo "Conflict detected during rebase. Resolving interactively..."
    while true; do
        if git diff --name-only --diff-filter=U | grep .; then
            echo "Conflicts detected. Resolving interactively..."
            CONFLICT_FILES=$(git diff --name-only --diff-filter=U)
            for FILE in $CONFLICT_FILES; do
                echo "Opening file for conflict resolution: $FILE"
                vim "$FILE"  # Open file in vim
                git add "$FILE"
            done
            git rebase --continue || true
        else
            break
        fi
    done
fi

echo "Rebase complete. Pushing updated main branch to origin..."
git push origin master

echo "Process completed successfully."

