#!/bin/bash
set -euo pipefail
# Original script by Pawel Krupa (@paulfantom)
# https://github.com/cloudalchemy/ansible-grafana/blob/7bb4a6f57740edfaeec24184f62d4b62035bbe58/.travis/releaser.sh
# Update by rockandska
#
# Script to automatically do a couple of things:
#   - generate a new tag according to semver (https://semver.org/)
#   - generate CHANGELOG.md by using https://github.com/skywinder/github-changelog-generator
#
# Tags are generated by searching for a keyword in last commit message. Keywords are:
#  - [patch] or [fix] to bump patch number
#  - [minor], [feature] or [feat] to bump minor number
#  - [major] or [breaking change] to bump major number
# All keywords MUST be surrounded with square braces.
#
# Requirements:
#   - GIT_TOKEN variable set with GitHub token. Access level: repo.public_repo
#   - docker
#   - git-semver python package (pip install git-semver)

##################
# User variables #
##################

: ${GIT_TOKEN:?}
: ${GIT_REPOSITORY_TYPE:=github}
: ${GIT_REMOTE:=$(git config --get remote.origin.url)}
: ${GIT_EMAIL:=$(git show -s --format='%ae')}
: ${GIT_USER:=$(git show -s --format='%an')}
: ${GIT_COMMIT:=$(git rev-parse HEAD)}
: ${GIT_COMMIT_MESSAGE:=$(git rev-list --format=%B --max-count=1 ${GIT_COMMIT} | tail -n +2)}
: ${GIT_DEFAULT_BRANCH:=master}

###############################################
# Skipping if commit is already part of a tag #
###############################################
GIT_TAGS=($(git tag --contains 2> /dev/null))
[[ ! "${#GIT_TAGS[@]}" -ne 0 ]] \
  || { echo 1>&2 "Commit '${GIT_COMMIT}' is already part of '$(printf "%s " ${GIT_TAGS[@]})'tag(s). Skipping...."; exit 0; }

################
# Parse remote #
################

[[ "${GIT_REMOTE}" =~ ^(([^:/]+)://)?(([^/:@]+)?(:([^/:@]+))?@)?([^~/:@]+)?(:(\d+))?:?(.*)/([^/]+)/?$ ]] \
  || { echo 1>&2 "Fatal: could not parse remote ${GIT_REMOTE}"; exit 1; }

: ${GIT_DOMAIN:=${BASH_REMATCH[7]}}
: ${GIT_PROTOCOL:=${BASH_REMATCH[2]}}
: ${GIT_URI:=${BASH_REMATCH[10]#/}}
: ${GIT_NAMESPACE:=${GIT_URI}}
: ${GIT_PROJECT:=${BASH_REMATCH[11]/.git}}

#############################
# Do some conditional tests #
#############################

# commit_message !~ /\[skip\]/
[[ ! "${GIT_COMMIT_MESSAGE}" =~ .*(\[(ci skip|skip-mkrelease)\]).* ]] \
  || { echo 1>&2 "Found ${BASH_REMATCH[1]} in commit message. Skipping....."; exit 0; }

# branch = master
[[ $(git branch --contains ${GIT_COMMIT} | grep " ${GIT_DEFAULT_BRANCH}$") ]] \
  || { status=$?; echo 1>&2 "Fatal: $0 should only be launch on commit part of '${GIT_DEFAULT_BRANCH}' branch !"; exit 1; }

#############
# Git config
#############

git config user.name "${GIT_USER}"
git config user.name "${GIT_EMAIL}"

#######
# Tag generation
#######

GIT_TAG=none
EXISTING_TAGS=($(git tag))

echo "Last commit message: ${GIT_COMMIT_MESSAGE}"
case "${GIT_COMMIT_MESSAGE}" in
  *"[patch]"*|*"[fix]"* )
    if [[ ${#EXISTING_TAGS[@]} -eq 0 ]];then
      GIT_TAG=0.0.1
    else
      GIT_TAG=$(git semver --next-patch)
    fi
    ;;
  *"[minor]"*|*"[feat]"*|*"[feature]"* )
    if [[ ${#EXISTING_TAGS[@]} -eq 0 ]];then
      GIT_TAG=0.1.0
    else
      GIT_TAG=$(git semver --next-minor)
    fi
    ;;
  *"[major]"*|*"[breaking change]"* )
    if [[ ${#EXISTING_TAGS[@]} -eq 0 ]];then
      GIT_TAG=1.0.0
    else
      GIT_TAG=$(git semver --next-major)
    fi
    ;;
  *)
    echo "Keyword not detected. Doing nothing"
    ;;
esac

########
# Changelog / Tag generation
########

git checkout ${GIT_DEFAULT_BRANCH}

if [[ "${GIT_REPOSITORY_TYPE}" == "github" ]];then
  ############
  # GITHUB
  ############
  GIT_PUSH_URL="https://${GIT_TOKEN}:@github.com/${GIT_URI}/${GIT_PROJECT}.git"
  GIT_RELEASE_URL="https://github.com/${GIT_NAMESPACE}/${GIT_PROJECT}/tree/%s"
  if [ "${GIT_TAG}" != "none" ]; then
    echo "Generate CHANGELOG.md for the release '${GIT_TAG}'"
    docker run -it --rm -v "$(pwd)":/usr/local/src/your-app ferrarimarco/github-changelog-generator:1.14.3 \
                  -u "${GIT_NAMESPACE}" -p "${GIT_PROJECT}" --token "${GIT_TOKEN}" \
                  --release-url "${GIT_RELEASE_URL}" --future-release "${GIT_TAG}" \
                  --unreleased-label "**Next release**" --no-compare-link
    git add CHANGELOG.md
    git commit -m "Bump version to ${GIT_TAG} [skip-mkrelease]"
    echo "Assigning new tag: ${GIT_TAG}"
    git tag "${GIT_TAG}" -a -m "Automatic tag generation"
    if ! git ls-remote --exit-code origin refs/tags/${GIT_TAG} 2> /dev/null;then
      git push ${GIT_PUSH_URL} --follow-tags
    else
      { echo 1>&2 "Fatal: Tag '${GIT_TAG}' already exist on remote."; exit 1; }
    fi
    echo "Version '${GIT_TAG}' pushed to '${GIT_NAMESPACE}/${GIT_PROJECT}'"
  else
    echo "Generate CHANGELOG.md for unreleased"
    docker run -it --rm -v "$(pwd)":/usr/local/src/your-app ferrarimarco/github-changelog-generator:1.14.3 \
                  -u "${GIT_NAMESPACE}" -p "${GIT_PROJECT}" --token "${GIT_TOKEN}" \
                  --release-url "${GIT_RELEASE_URL}" \
                  --unreleased-label "**Next release**" --no-compare-link
    git add CHANGELOG.md
    git commit -m "Automatic changelog update [ci skip]"
    git push ${GIT_PUSH_URL}
    echo "Changelog updated pushed to '${GIT_NAMESPACE}/${GIT_PROJECT}'"
  fi
elif [[ "${GIT_REPOSITORY_TYPE}" == "gitlab" ]];then
  ############
  # GITLAB
  ############
  GIT_PUSH_URL="${GIT_PROTOCOL}://oauth2:${GIT_TOKEN}@${GIT_DOMAIN}/${GIT_URI}/${GIT_PROJECT}.git"
  if [ "${GIT_TAG}" != "none" ]; then
    echo "Assigning new tag: ${GIT_TAG}"
    git tag "${GIT_TAG}" -a -m "Automatic tag generation"
    git push ${GIT_PUSH_URL} --follow-tags
  fi
else
  echo 1>&2 "Git repository type ('${GIT_REPOSITORY_TYPE}') is not recognized"
  exit 1
fi
