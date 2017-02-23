#!/bin/sh
#
# gluon-nightly-build - create nightly-build gluon firmware
# 
# This script will build and deplay new firmware version based on
# gluon git repository. A new version is only build if git repository
# has new commits.
#
# Copyright Freifunk Erfurt, 2016-2017
# Marcel Pennewiss <opensource@pennewiss.de>
#
# Version: 1.1
# Last-Modified: 2017-02-23
#
# REQUIREMENTS:
#   * git
#   * rsync
#
# EXIT CODES:
#   0 - Build successfull / No build needed
#   1 - Build failed
#   2 - GIT errors


#######################################################
# CONFIGURATION
#######################################################

# Log stdout
# param $1 output
logStdout() {
  if [ ${QUIET:-0} -eq 0 ]; then
    logger -t gluon-nightly-build "${1}"
    echo "${1}"
  fi
}

# Log stderr
# param $1 output
logStderr() {
  logger -t gluon-nightly-build -s "${1}"
}

# Read configuration
read_configuration() {

  SCRIPT_DIRECTORY=$(dirname $(readlink -f ${0}))

  . $(dirname ${0})/gluon-nightly-build.config 2>/dev/null
  if [ $? -ne 0 ]; then
    logStderr "Configuration file ${SCRIPT_DIRECTORY}/gluon-nightly-build.config file not found." >&2
    exit 1
  fi
}

prepare() {

  # Prepare variables
  MAKE_GLUON_TARGETS=""

  # check for installed git
  which git > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    logStderr "GIT not found! Please install." >&2
    exit 1
  fi

  # check for installed rsync
  which rsync > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    logStderr "RSYNC not found! Please install." >&2
    exit 1
  fi

  # Build broken
  if [ "$BUILD_BROKEN" != "0" ] && [ "$BUILD_BROKEN" != "1" ]; then
    logStderr "BUILD_BROKEN must be 0 or 1."
    exit 1
  fi

  # Check buildroot
  if [ ! -d "$BUILD_DIRECTORY" ]; then
    logStderr "Buildroot directory $BUILD_DIRECTORY not found."
    exit 1
  fi

  # Check image mirror directory
  if [ ! -d "$MIRROR_DIRECTORY" ]; then
    logStderr "Mirror directory $MIRROR_DIRECTORY not found."
    exit 1
  fi

  # Check sign key
  if [ ! -e "$BUILD_SIGNKEY" ]; then
    logStderr "Sign key $BUILD_SIGNKEY not found."
    exit 1
  fi

  if [ -z "$BUILD_BRANCH" ]; then
    logStderr "Build branch must be configured."
    exit 1
  fi

}

# Check for commits in git repository
# return int (0 - no new commits, 1 - new commits) 
check_git_commits() {

  cd "${BUILD_DIRECTORY}"

  logStdout "GIT: Checking for updates..."

  # Update repository
  git remote update > /dev/null 2>&1
  [ $? -ne 0 ] && logStderr "GIT: Remote update failed." && exit 2

  # Get last local and remote commit
  GIT_LOCAL_COMMIT=$(git rev-parse @)
  GIT_REMOTE_COMMIT=$(git rev-parse @{u})

  # Compare local and remote
  if [ $GIT_REMOTE_COMMIT = $GIT_LOCAL_COMMIT ]; then
    logStdout "GIT: No updates found."
    return 0
  else
    logStdout "GIT: New commits found."
    logStdout "GIT: Last local commit: $GIT_LOCAL_COMMIT, last remote commit: $GIT_REMOTE_COMMIT"
    return 1
  fi

}

# Update git to last recent commit
update_git() {

  cd "${BUILD_DIRECTORY}"
    
  logStdout "GIT: Reset local repository to latest upstream commit."

  git pull --quiet
  [ $? -ne 0 ] && logStderr "GIT: Pull of repository failed." && exit 2

  git reset --hard origin/master --quiet
  [ $? -ne 0 ] && logStderr "GIT: Reset of repository to origin/master failed." && exit 2
 
}

# Get GluonTargets which are not totally broken
get_gluontargets() {

  logStdout "BUILD: Get working gluon targets for make..."

  cd "${BUILD_DIRECTORY}"
  while read LINE; do
    case "$LINE" in
      *GluonTarget*\)\))
        MAKE_GLUON_TARGETS="$MAKE_GLUON_TARGETS $(echo "$LINE" | sed -e 's/.* GluonTarget,\([^,]*\),\([^,]*\).*))$/\1\-\2/')"
        ;;
    esac
  done < targets/targets.mk

  logStdout "BUILD: GluonTargets found: $MAKE_GLUON_TARGETS"
}

build_gluontargets() {

  # Get all known GluonTargets
  get_gluontargets
  [ -z "$MAKE_GLUON_TARGETS" ] && logStderr "BUILD: No GluonTargets found." && exit 1

  # Update dependencies
  cd "${BUILD_DIRECTORY}"
  make update
  [ $? -ne 0 ] && logStderr "BUILD: make update failed." && exit 1

  # Build Targets
  for GLUON_TARGET in $MAKE_GLUON_TARGETS; do
    logStdout "BUILD: Start to build target $GLUON_TARGET..."
    #make $BUILD_MAKE_OPTS GLUON_TARGET=$GLUON_TARGET GLUON_BRANCH=$BUILD_BRANCH BROKEN=$BUILD_BROKEN
    make $BUILD_MAKE_OPTS GLUON_TARGET=$GLUON_TARGET BROKEN=$BUILD_BROKEN
    [ $? -ne 0 ] && logStderr "BUILD: Error building target $GLUON_TARGET" && exit 1
  done

}

# Create manifest und sign image with key
sign_images() {

  cd "${BUILD_DIRECTORY}"
  
  logStdout "BUILD: Create manifest and sign images..."

  # Create manifest
  make manifest GLUON_BRANCH=$BUILD_BRANCH
  [ $? -ne 0 ] && logStderr "BUILD: Error creating manifest" && exit 1

  # Sign upgrade
  contrib/sign.sh $BUILD_SIGNKEY output/images/sysupgrade/$BUILD_BRANCH.manifest
  [ $? -ne 0 ] && logStderr "BUILD: Signing images failed." && exit 1

}

# Deploy images
deploy_images() {

  cd "${BUILD_DIRECTORY}"

  logStdout "BUILD: Deploy images to mirror directory..."

  # Sync images to mirror directory
  rsync --archive --delete "$BUILD_DIRECTORY/output/images/" "$MIRROR_DIRECTORY/"
  [ $? -ne 0 ] && logStderr "BUILD: Deploying images failed." && exit 1

  # Create module directory
  GLUON_RELEASE=$(ls "${BUILD_DIRECTORY}/output/modules/" 2>/dev/null)
  [ -z "$GLUON_RELEASE" ] && logStderr "BUILD: Module directory not found" && exit 1

  # Create module 
  mkdir "$MIRROR_DIRECTORY/modules/" 2>/dev/null

  # Sync modules to mirror directory
  rsync --archive --delete "$BUILD_DIRECTORY/output/modules/$GLUON_RELEASE/" "$MIRROR_DIRECTORY/modules/"
  [ $? -ne 0 ] && logStderr "BUILD: Deploying images failed." && exit 1

}

read_configuration
prepare

# Check possible arguments
[ "$1" = "--quiet" ] && QUIET=1

# Check for updates
check_git_commits
[ $? -eq 0 ] && exit 0

update_git
build_gluontargets
sign_images
deploy_images
exit 0
