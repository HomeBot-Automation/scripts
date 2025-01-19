#!/bin/bash

# Exit on any error
set -e

# Helper function to resolve conflicts in a file using awk
resolve_conflicts_in_file() {
    local file=$1

    echo "Resolving conflicts in file: $file"

    awk -v OFS="\n" -v file="$file" '
        BEGIN {
            in_conflict = 0;
            conflict_block = "";
        }
        /<<<<<<< HEAD/ {
            in_conflict = 1;
            conflict_block = $0 "\n";
            next;
        }
        /=======/ && in_conflict {
            ours = conflict_block;
            gsub(/^<<<<<<< HEAD\n/, "", ours);
            gsub(/\n=======\n.*/, "", ours);
            conflict_block = conflict_block "\n" $0 "\n";
            next;
        }
        />>>>>>>/ && in_conflict {
            theirs = conflict_block;
            gsub(/^.*\n=======\n/, "", theirs);
            gsub(/\n>>>>>>>.*/, "", theirs);
            conflict_block = conflict_block "\n" $0;

            print "==== OURS ====\n" ours > "/dev/stderr";
            print "==== THEIRS ====\n" theirs > "/dev/stderr";

            # Prompt user for resolution
            while (1) {
                printf "Choose resolution (o=ours, t=theirs, e=edit entire file, default=theirs): " > "/dev/stderr";
                getline choice < "/dev/tty";
                if (choice == "o" || choice == "O") {
                    resolved_block = ours;
                    print "Resolved using OURS." > "/dev/stderr";
                    break;
                } else if (choice == "t" || choice == "T" || choice == "") {
                    resolved_block = theirs;
                    print "Resolved using THEIRS (default)." > "/dev/stderr";
                    break;
                } else if (choice == "e" || choice == "E") {
                    # Allow user to edit the entire file
                    system("vim " file " < /dev/tty > /dev/tty 2>&1");
                    print "Resolved by editing the entire file." > "/dev/stderr";
                    exit;  # Exit AWK to avoid further processing
                } else {
                    print "Invalid choice. Please enter 'o', 't', 'e', or press Enter for default (theirs)." > "/dev/stderr";
                }
            }

            # Print the resolved block
            print resolved_block;

            in_conflict = 0;
            conflict_block = "";
            next;
        }
        in_conflict {
            conflict_block = conflict_block "\n" $0;
            next;
        }
        {
            print $0;
        }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"

    # Check if any conflict markers remain
    if grep -q "<<<<<<< HEAD" "$file"; then
        echo "Unresolved conflicts remain in $file."
    else
        echo "No remaining conflict tags in $file. Saving file."
    fi
}

# Function to handle rebase or cherry-pick with conflicts
handle_git_operation_with_conflicts() {
    local operation=$1
    echo "Handling $operation with conflict resolution..."
    while true; do
        if git diff --name-only --diff-filter=U | grep .; then
            # Get a list of files with conflicts
            conflict_files=$(git diff --name-only --diff-filter=U)
            for file in $conflict_files; do
                resolve_conflicts_in_file "$file"
                git add "$file"
            done
            git "$operation" --continue || true
        else
            break
        fi
    done
    echo "$operation complete."
}

# Main script logic
if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <supervisor-repo> <addon-repo> <core-repo> <frontend-repo>"
    exit 1
fi

REPOS=("$1" "$2" "$3" "$4")
BRANCHES=("main" "master" "dev" "dev")

for i in "${!REPOS[@]}"; do
    REPO_PATH=$(realpath "${REPOS[$i]}")
    BRANCH="${BRANCHES[$i]}"

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

    # Fetch updates and tags from upstream
    echo "Fetching updates and tags from upstream..."
    git fetch --force --tags upstream

    # Push all tags from upstream to origin
    echo "Pushing all upstream tags to origin..."
    git push --force origin --tags

    # Sync branch
    echo "Switching to $BRANCH branch..."
    git checkout "$BRANCH"

    echo "Rebasing $BRANCH onto upstream/$BRANCH to preserve changes..."
    if ! git rebase "upstream/$BRANCH"; then
        echo "Conflict detected during rebase. Resolving interactively..."
        handle_git_operation_with_conflicts "rebase"
    fi

    echo "Rebase complete. Pushing updated $BRANCH branch to origin..."
    git push --force-with-lease origin "$BRANCH"

    # Find the latest tag
    LATEST_TAG=$(git describe --tags "$(git rev-list --tags --max-count=1)" 2>/dev/null || true)
    if [ -z "$LATEST_TAG" ]; then
        echo "No tags found in the repository. Skipping tag-based operations for $REPO_PATH."
        continue
    fi

    echo "Latest tag found: $LATEST_TAG"

    # Check for unique commits
    if git diff --stat "origin/$BRANCH" "upstream/$BRANCH" | grep -q '.'; then
        UNIQUE_COMMITS=$(git log "origin/$BRANCH" ^"upstream/$BRANCH" --oneline | awk '{print $1}')
    else
        UNIQUE_COMMITS=""
    fi

    if [ -n "$UNIQUE_COMMITS" ]; then
        echo "Unique commits found: $UNIQUE_COMMITS"

        # Check and clean up leftover branch
        NEW_BRANCH="updated-with-latest-tag"
        if git rev-parse --verify --quiet "$NEW_BRANCH"; then
            echo "Deleting leftover branch ($NEW_BRANCH)..."
            git branch -D "$NEW_BRANCH"
        fi

        # Create a new branch for cherry-picking unique commits
        echo "Creating a new branch ($NEW_BRANCH) based on $LATEST_TAG..."
        git checkout -b "$NEW_BRANCH" "$LATEST_TAG"

        # Cherry-pick unique commits onto the new branch
        for COMMIT in $UNIQUE_COMMITS; do
            echo "Cherry-picking commit: $COMMIT"
            if ! git cherry-pick "$COMMIT"; then
                echo "Conflict detected during cherry-pick. Resolving interactively..."
                handle_git_operation_with_conflicts "cherry-pick"
            fi
        done

        # Update the latest tag with unique commits
        echo "Updating the tag ($LATEST_TAG) with unique commits..."
        git tag -f -a "$LATEST_TAG" -m "Updated $LATEST_TAG with unique commits"

        # Push the updated tag to origin
        echo "Pushing updated tag to origin..."
        git push --force origin "$LATEST_TAG"

        # Switch back to the branch
        echo "Switching back to $BRANCH branch..."
        git checkout "$BRANCH"

        # Delete the temporary branch
        echo "Deleting temporary branch ($NEW_BRANCH)..."
        git branch -D "$NEW_BRANCH"
    else
        echo "No unique commits to inject into the latest tag for $REPO_PATH."
    fi
done

echo "Process completed successfully for all repositories."

