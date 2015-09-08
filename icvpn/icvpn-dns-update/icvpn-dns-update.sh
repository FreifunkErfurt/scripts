#!/bin/sh
#
# icvpn-dns-update - update dns configuration for ICVPN zones
# 
# This script will update dns configuration file for ICVPN zone
# using icvpn-meta/icvpn-scripts repository on github
#
# Copyright Freifunk Erfurt, 2015
# Marcel Pennewiss <opensource@pennewiss.de>
#
# Version: 1.0
# Last-Modified: 2015-08-29
#
# REQUIREMENTS:
#   * git
#
# EXIT CODES:
#   0 - Update successfull or not necessary
#   1 - Update failed due to git errors
#   2 - Update failed due to prerequirement errors
#   3 - Update failed due nameserver errors
#
#######################################################
# CONFIGURATION
#######################################################

. $(dirname ${0})/icvpn-dns-update.config 2>/dev/null
if [ $? -ne 0 ]; then
  echo "Configuration file $(dirname $(readlink -f ${0}))/icvpn-dns-update.config file not found." >&2
  exit 2
fi

# mkdns-script
DNSSERVER_SCRIPT=$(dirname ${0})/icvpn-scripts/mkdns

# GIT repositories
GIT_ICVPN_META="https://github.com/freifunk/icvpn-meta.git"
GIT_ICVPN_SCRIPTS="https://github.com/freifunk/icvpn-scripts.git"

# Repository base dir
GIT_REPOS_BASEDIR=/tmp/icvpn-git

#######################################################
# PROGRAM
#######################################################

# Get current commit id from local repository
# param $1 path to repository
getCurrentCommitId() {

  # Repository directory
  local GIT_REPOS_DIRECTORY=$(getGitReposDirectory $1)

  if [ -n ${1} ]; then
    GITOPTIONS="--git-dir=${GIT_REPOS_DIRECTORY}/.git"
  fi

  git ${GITOPTIONS} rev-parse HEAD

}

# Get repository work directory
# param $1 repository uri
getGitReposDirectory() {
  # Return repository directory
  echo "${GIT_REPOS_BASEDIR}/${1##*\/}"
}

# Update repository
#
# Updates repository in directory. If directory not exists
# or is not an git repository the repository will be cloned.
#
# param $1 repository uri
# return int
#   0: repository unchanged
#   1: repository changed/newly cloned
#   2: error
updateGitRepos() {

  # local status
  local STATUS=0

  # Repository directory
  local GIT_REPOS_DIRECTORY=$(getGitReposDirectory ${1})

  # Clone git repository if directory not found, pull otherwise
  if [ ! -d ${GIT_REPOS_DIRECTORY} ]; then
    # Clone git repository if directory not found
    STATUS=1
    git clone ${1} ${GIT_REPOS_DIRECTORY} --quiet
    [ $? -ne 0 ] && STATUS=2
  else
    # Pull git repository and check for updates
    local LAST_COMMIT_ID=$(getCurrentCommitId ${1})
    git --git-dir=${GIT_REPOS_DIRECTORY}/.git pull --quiet
    [ $? -ne 0 ] && STATUS=2
    [ "${LAST_COMMIT_ID}" != "$(getCurrentCommitId ${1})" ] && STATUS=1
  fi

  return ${STATUS}
}

# Update DNS
updateDNS() {

  # return value of dns reload
  local RETURN

  # create new ICVPN DNS config
  ${DNSSERVER_SCRIPT} --sourcedir=$(getGitReposDirectory ${GIT_ICVPN_META}) --format=${DNSSERVER_TYPE} --exclude=${COMMUNITY} > ${DNSSERVER_CONF}

  # restart/reload dns server
  case ${DNSSERVER_TYPE} in

    bind|bind-forward)
      # reload bind config
      rndc reload > /dev/null
      RETURN=$?
      ;;

    dnsmasq)
      # restart dnsmasq
      if [ $(which systemctl 2>/dev/null) ]; then
        systemctl restart dnsmasq.service > /dev/null
      else
        /etc/init.d/dnsmasq restart > /dev/null
      fi
      RETURN=$?
      ;;

    unbound)
      # reload config
      unbound-control reload > /dev/null
      RETURN=$?
      ;;

  esac

  if [ ${RETURN} -ne 0 ]; then
    echo "Nameserver configuration could not be reloaded." >&2
    exit 3
  fi
}

# Main update
update() {

  # error flag
  local ERROR=0

  # check if config directory exists
  if [ ! -d $(dirname ${DNSSERVER_CONF}) ]; then
    echo "Nameserver configuration $(dirname ${DNSSERVER_CONF}) directory not found" >&2
    exit 2
  fi

  # check if mkdns exists
  if [ ! -e ${DNSSERVER_SCRIPT} ]; then
    echo "icvpn-scripts (or mkdns) not found in ${DNSSERVER_SCRIPT}" >&2
    echo "Cloning icvpn-scripts repository initially..." >&2
    git clone ${GIT_ICVPN_SCRIPTS} "$(dirname $(readlink -f ${0}))/icvpn-scripts"
    if [ $? -ne 0 ]; then
      echo "git clone of icvpn-scripts failed." >&2
      echo "Please run \"git clone ${GIT_ICVPN_SCRIPTS}\" manually in script directory" >&2
      exit 2
    fi
  fi

  # check if mkdns exists and is executable
  if [ ! -x ${DNSSERVER_SCRIPT} ]; then
    echo "mkdns not found or not executable in ${DNSSERVER_SCRIPT}" >&2
    exit 2
  fi

  # Check for new script repository, notify if updates available
  updateGitRepos ${GIT_ICVPN_SCRIPTS}
  local RETURN_SCRIPT_REPOS=$?
  if [ ${RETURN_SCRIPT_REPOS} -eq 2 ]; then
    echo "Update of icvpn-script repository failed." >&2
    ERROR=1
  elif [ ${RETURN_SCRIPT_REPOS} -eq 1 ]; then
    # Get last notify commit id
    local LAST_COMMIT_NOTIFY=""
    if [ -e ${GIT_REPOS_BASEDIR}/notify-scripts-commit-id ]; then
      LAST_COMMIT_NOTIFY=$(cat ${GIT_REPOS_BASEDIR}/notify-scripts-commit-id)
    fi
    # notify only on really new commit (prevent multiple notifies)
    if [ "${LAST_COMMIT_NOTIFY}" != "$(getCurrentCommitId ${GIT_ICVPN_SCRIPTS})" ]; then
      echo "NEW UPDATES available on icvpn-script repository!"
      echo $(getCurrentCommitId ${GIT_ICVPN_SCRIPTS}) > ${GIT_REPOS_BASEDIR}/notify-scripts-commit-id
    fi
  fi

  # Update meta repository
  updateGitRepos ${GIT_ICVPN_META}
  local RETURN_META_REPOS=$?
  if [ ${RETURN_META_REPOS} -eq 2 ]; then
    echo "Update of icvpn-meta repository failed." >&2
    exit 1
  fi

  # Update DNS information if meta repository changed
  [ ${RETURN_META_REPOS} -eq 1 ] && updateDNS
}

update
