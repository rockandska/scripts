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
#   - the repository to publish checkout on a tagged commit

##################
# User variables #
##################

: ${GIT_TOKEN:?}
: ${GIT_REPOSITORY_TYPE:=github}
: ${GIT_DEFAULT_BRANCH:=master}
: ${GIT_EMAIL:=$(git show -s --format='%ae')}
: ${GIT_USER:=$(git show -s --format='%an')}

git_remote=$(git config --get remote.origin.url)
git_commit=$(git rev-parse HEAD)
git_commit_message=$(git rev-list --format=%B --max-count=1 ${git_commit} | tail -n +2)

################
# Parse remote #
################

[[ "${git_remote}" =~ ^(([^:/]+)://)?(([^/:@]+)?(:([^/:@]+))?@)?([^~/:@]+)?(:(\d+))?:?(.*)/([^/]+)/?$ ]] \
  || { >&2 echo "Fatal: could not parse remote ${git_remote}"; exit 1; }

git_domain=${BASH_REMATCH[7]}
git_protocol=${BASH_REMATCH[2]}
git_uri=${BASH_REMATCH[10]#/}
git_namespace=${git_uri}
git_project=${BASH_REMATCH[11]/.git}


#############################
# Do some conditional tests #
#############################

# tagged commit
git_current_tag=$(git describe --exact-match 2> /dev/null || true)
[[ -n "${git_current_tag}" ]] \
  || { >&2 echo "Fatal: should be run only on tagged commit, but no tag was found !"; exit 1; }

while [[ $# -gt 0 ]];do
  key="$1"
  case $key in
      ansible-galaxy)
        ansible_galaxy=1
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
  >&2 echo "Sync changelog to github releases"
  [[ "${PUBRELEASE_DUMMY:=0}" -eq 0 ]] && docker run -e CHANDLER_GITHUB_API_TOKEN="${GIT_TOKEN}" -v "$(pwd)":/chandler -ti whizark/chandler push "${git_current_tag}"

  if [[ ${ansible_galaxy:=0} -eq 1 ]];then
    >&2 echo "Import role to galaxy"
    ansible-galaxy login --github-token="${GIT_TOKEN}"
    [[ "${PUBRELEASE_DUMMY:=0}" -eq 0 ]] && ansible-galaxy import "${git_namespace}" "${git_project}"
  fi
fi
