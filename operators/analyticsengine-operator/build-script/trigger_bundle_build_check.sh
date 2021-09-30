#!/bin/bash

set -e

git fetch origin master:refs/remotes/origin/master # Fetch master to compare with master

git diff --name-only origin/master...${TRAVIS_COMMIT}
CHANGED_FILES=`git diff --name-only origin/master...${TRAVIS_COMMIT}`
ONLY_READMES=True
MD=".md"

count=0
for CHANGED_FILE in $CHANGED_FILES; do
  if ! [[ $CHANGED_FILE =~ $MD ]]; then
    count=$((count+1))
    ONLY_READMES=False
    break
  fi
done

echo $count

if [[ ($ONLY_READMES == True && $count == 1)]]; then
  echo "Only .md files changes found, exiting."
  exit 1
else
  echo "Non-.md files found, continuing with build."
  exit 0
fi