#!/bin/bash

GITHUB_EVENT_ACTION="$1"
GITHUB_REPOSITORY="$2"
GH_TOKEN="$3"

# Configure Git
git config --global user.email "actions@github.com"
git config --global user.name "GitHub Actions"

# Determine Version
base_branch=$(jq -r .pull_request.base.ref "$GITHUB_EVENT_PATH")
branch_name=$(jq -r .pull_request.head.ref "$GITHUB_EVENT_PATH")

if [[ $base_branch == 'qa' ]]; then
  if [[ $branch_name == 'dev' ]]; then
    if [[ $GITHUB_EVENT_ACTION == 'closed' && $(jq -r '.pull_request.merged' "$GITHUB_EVENT_PATH") == 'true' ]]; then
      dev_version_json=$(git show origin/dev:package.json)
      dev_version=$(echo "$dev_version_json" | jq -r .version)
      dev_minor=$(echo "$dev_version" | cut -d. -f2)
      echo "Versión minor dev: $dev_minor"

      qa_version=$(git show refs/heads/qa:package.json | jq -r .version)
      qa_minor=$(echo "$qa_version" | cut -d. -f2)
      echo "Versión minor qa: $qa_minor"

      if [[ $dev_minor == $qa_minor ]]; then
        npm --no-git-tag-version version preminor --preid=beta
      else
        npm --no-git-tag-version version prerelease --preid=beta
      fi
    fi
  elif [[ $branch_name == *fix/* ]]; then
    if [[ $GITHUB_EVENT_ACTION == 'closed' && $(jq -r '.pull_request.merged' "$GITHUB_EVENT_PATH") == 'true' ]]; then
      npm version prepatch --preid=beta
    fi
  fi
elif [[ $base_branch == 'master' ]]; then
  if [[ $branch_name == 'qa' ]]; then
    if [[ $GITHUB_EVENT_ACTION == 'closed' && $(jq -r '.pull_request.merged' "$GITHUB_EVENT_PATH") == 'true' ]]; then
      npm version minor
    fi
  elif [[ $branch_name == *fix/* ]]; then
    if [[ $GITHUB_EVENT_ACTION == 'closed' && $(jq -r '.pull_request.merged' "$GITHUB_EVENT_PATH") == 'true' ]]; then
      npm version patch
    fi
  fi
fi

# Set Outputs
echo "::set-output name=base_branch::$base_branch"
echo "::set-output name=branch_name::$branch_name"

# Get New Version
version=$(npm version)
echo "::set-output name=version::$version"

# Commit and Push Version Update
base_branch=${base_branch:-'master'}
branch_name=${branch_name:-'dev'}
echo "Base branch: $base_branch"
echo "Branch name: $branch_name"
echo "Version: $version"

git fetch origin "$base_branch":"$base_branch" || true
git checkout "$base_branch" || true

git add .
git commit -am "Update version" || true
git checkout "$base_branch"
git push origin "$base_branch" --follow-tags || true

# Reintegrate Changes
if [[ $GITHUB_EVENT_ACTION == 'closed' && $(jq -r '.pull_request.merged' "$GITHUB_EVENT_PATH") == 'true' && $(jq -r '.pull_request.base.ref' "$GITHUB_EVENT_PATH") == 'master' ]]; then
  version=$(git describe --tags --abbrev=0 $(git rev-list --tags --max-count=1 master))
  reintegrate_branch="reintegrate/$version"

  git fetch origin master
  git checkout -b "$reintegrate_branch" master
  git push origin "$reintegrate_branch"

  PR_TITLE="Reintegrate $version to dev"

  curl -X POST \
    -H "Authorization: Bearer $GH_TOKEN" \
    -d '{"title":"'"$PR_TITLE"'","head":"'"$reintegrate_branch"'","base":"dev"}' \
    "https://api.github.com/repos/$GITHUB_REPOSITORY/pulls"
fi
