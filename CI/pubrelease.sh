#!/bin/bash
set -euo pipefail

# Script to automatically do a couple of things:
#   - sync CHANGELOG with GitHub releases by using https://github.com/mattbrictson/chandler
#   - import galaxy role if asked
#
# Requirements:
#   - GIT_TOKEN variable set with GitHub token. Access level: repo.public_repo
#   - docker
#   - ansible if importing into galaxy (pip install ansible)

# User variables
: ${GIT_TOKEN:?}
: ${GIT_REPOSITORY_TYPE:=github}
: ${GIT_REMOTE:=$(git config --get remote.origin.url)}
: ${GIT_EMAIL:=$(git show -s --format='%ae')}
: ${GIT_USER:=$(git show -s --format='%an')}
: ${GIT_COMMIT:=$(git rev-parse HEAD)}
: ${GIT_COMMIT_MESSAGE:=$(git rev-list --format=%B --max-count=1 ${GIT_COMMIT} | tail -n +2)}
: ${GIT_DEFAULT_BRANCH:=master}

# Parse remote
[[ "${GIT_REMOTE}" =~ ^(([^:/]+)://)?(([^/:@]+)?(:([^/:@]+))?@)?([^~/:@]+)?(:(\d+))?:?(.*)/([^/]+\.git) ]] \
  || echo 1>&2 "Fatal: could not parse remote ${GIT_REMOTE}"

: ${GIT_DOMAIN:=${BASH_REMATCH[7]}}
: ${GIT_PROTOCOL:=${BASH_REMATCH[2]}}
: ${GIT_URI:=${BASH_REMATCH[10]#/}}
: ${GIT_NAMESPACE:=${GIT_URI}}
: ${GIT_PROJECT:=${BASH_REMATCH[11]/.git}}

#######
# Do same conditional tests that in .travis.yml
# branch = master AND tag IS present
#######

[[ $(git branch --contains ${GIT_COMMIT} | grep " ${GIT_DEFAULT_BRANCH}$") ]] \
  || { status=$?; echo 1>&2 "Fatal: $0 should only be launch on '${GIT_DEFAULT_BRANCH}' branch !"; exit 1; }

GIT_CURRENT_TAG=$(git describe --exact-match 2> /dev/null || true)
[[ -n "${GIT_CURRENT_TAG}" ]] \
  || { echo 1>&2 "Fatal: should be run only on tagged commit, but no tag was found !"; exit 1; }


while [[ $# -gt 0 ]];do
  key="$1"
  case $key in
      ansible-galaxy)
        ANSIBLE_GALAXY=1
        shift
      ;;
      *)
        shift
        ;;
  esac
done

##########
# GITHUB
##########
if [[ "${GIT_REPOSITORY_TYPE}" == "github" ]];then
  echo "Sync changelog to github releases"
  docker run -e CHANDLER_GITHUB_API_TOKEN="${GIT_TOKEN}" -v "$(pwd)":/chandler -ti whizark/chandler push "${GIT_CURRENT_TAG}"

  if [[ ${ANSIBLE_GALAXY:=0} -eq 1 ]];then
    echo "Import role to galaxy"
    ansible-galaxy login --github-token="${GIT_TOKEN}"
    ansible-galaxy import "${GIT_NAMESPACE}" "${GIT_PROJECT}"
  fi
fi
