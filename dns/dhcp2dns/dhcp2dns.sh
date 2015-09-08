#!/bin/sh
#
# dhcp2dns - update dns entries after dhcp request
# 
# This script will update dns entries via nsupdate mechanism
# on multiple nameservers. It will also update reverse entries.
# The given ip will be checked agains dhcp ranges to ensure that
# update will not be triggered for non-dynamic zones.
#
# Copyright Freifunk Erfurt, 2015
# Marcel Pennewiss <opensource@pennewiss.de>
#
# Version: 1.0
# Last-Modified: 2015-06-07
#
# REQUIREMENTS:
#   * sipcalc
#   * tac (GNU coreutils)
#   * nsupdate (dnsutils)
#
# EXIT CODES:
#   0 - Update successfull
#   1 - Update not or only partly successfull
#   2 - Wrong parameters / IP not in DHCP Range

#######################################################
# CONFIGURATION
#######################################################

SCRIPT_DIRECTORY=$(dirname $(readlink -f ${0}))

. $(dirname ${0})/dhcp2dns.config 2>/dev/null
if [ $? -ne 0 ]; then
  echo "Configuration file ${SCRIPT_DIRECTORY}/dhcp2dns.config file not found." >&2
  exit 2
fi

#######################################################
# PROGRAM
#######################################################

# show usage information
printUsage() {
  echo "dhcp2dns v1.0"
  echo "Updates DNS entries via DDNS mechanism on a list of dns servers."
  echo ""
  echo "Usage $0 [OPTIONS]"
  echo ""
  echo " -a                  Add entry for NAME (-n) with given IPv4-ADDRESS (-i)"
  echo " -d                  Remove entry for NAME (-n) with given IPv4-ADDRESS (-i)"
  echo " -i <IPV4-ADDRESS>   IPv4-Address"
  echo " -n <NAME>           Name of the entry"
  echo " -q                  Be quiet (only error messages)"
  echo " -h                  Show this help"
  echo ""
}

# Log stdout
# param $1 Output
logStdout() {
  if [ ${QUIET:-0} -eq 0 ]; then
    logger -t updatedns "${1}"
    echo "${1}"
  fi
}

# Log stderr
# param $1 Output
logStderr() {
  logger -t updatedns -s "${1}"
}

# Check all parameters
checkParameters() {
  local ERROR_DETECTED=0

  # Check if add or remove option is set
  if [ $((${ADD:-0} + ${REMOVE:-0})) -ne 1 ]; then
    logStderr "No or two options for add/remove selected."
    ERROR_DETECTED=1
  fi

  # Check if IPv4 address and Name is set on add option
  if [ -z ${NAME} ] || [ -z {$IPADDRESS} ]; then
    logStderr "Name or IPv4 address not set, but needed for adding dns entry."
    ERROR_DETECTED=1
  fi

  # Exit if any error occurred
  if [ ${ERROR_DETECTED} -eq 1 ]; then
    exit 255
  fi

  # Check if IPv4 address is valid
  echo ${IPADDRESS} | grep -q -E -e "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.|$)){4}$"
  if [ $? -ne 0 ] && [ -n "${IPADDRESS}" ]; then
    logStderr "IPv4-Address \"${IPADDRESS}\" not valid."
    ERROR_DETECTED=1
  fi

  # Check if name is valid as per RFC1123
  echo ${NAME} | grep -q -x -E -e "^[A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9]$"
  if [ $? -ne 0 ] && [ -n "${NAME}" ]; then
    logStderr "DNS-Name \"${NAME}\" not valid."
    ERROR_DETECTED=1
  fi

  # Check if IPv4 address is part of a dhcp range
  isInDhcpRange
  if [ $? -ne 0 ]; then
    logStderr "${IPADDRESS} is not part of a dhcp range"
    ERROR_DETECTED=1
  fi

  # Exit if any error occurred
  if [ ${ERROR_DETECTED} -eq 1 ]; then
    exit 2
  fi
}

# Determine whether an ip address is in dhcp ranges or not
# return 0 - in DHCP range, 1 - not in DHCP range
isInDhcpRange() {
  # try to find matching dhcp range
  for RANGE in ${DHCP_RANGES}; do
    NETWORK_RANGE=${RANGE%/*}
    NETMASK=${RANGE##*/}
    NETWORK_IPADDRESS=$(sipcalc ${IPADDRESS}/${NETMASK} | grep -e "^Network address" | cut -d'-' -f2 | sed -e 's/\ //g')
    if [ "${NETWORK_RANGE}" = "${NETWORK_IPADDRESS}" ]; then
      return 0
    fi
  done

  # no match found
  return 1
}

# determine reverse zone (based on IPv4 address)
# return reverse zone
getReverseZone() {
  echo $(printf %s "$(echo "${IPADDRESS}" | cut -d'.' -f-${DOMAIN_REVERSE_OCTETS})." | tac -s.)in-addr.arpa
}

# determine reverse entry (based on IPv4 address)
# return reverse entry
getReverseEntry() {
  local 
  echo $(printf %s "${IPADDRESS}." | tac -s.)in-addr.arpa
}

# run nsupdate
# param $1 Operation (add/remove)
# param $2 Command to send via nsupdate
# return 0 - successfull, 1 - single update failed, 2 - all updates failed
updateDnsEntry() {
  local COMMAND
  local COUNT_SERVERS=0
  local COUNT_SERVERS_SUCCESSFULL=0

  # build commands for nsupdate (without server statement)
  COMMAND="zone ${2}\n"
  COMMAND="${COMMAND}${3}\n"
  COMMAND="${COMMAND}send"

  for SERVER in ${DNS_SERVERS}; do
    COUNT_SERVERS=$((COUNT_SERVERS+1))
    printf "%b\n" "server ${SERVER}\n${COMMAND}" | nsupdate -t 5 -u 5 -v
    if [ $? -eq 0 ]; then
      COUNT_SERVERS_SUCCESSFULL=$((COUNT_SERVERS_SUCCESSFULL+1))
      logStdout "Update DNS entry (${1}) for server ${SERVER} successfull."
    else
      logStderr "Update DNS entry (${1}) for server ${SERVER} failed."
    fi
  done

  if [ ${COUNT_SERVERS} -eq ${COUNT_SERVERS_SUCCESSFULL} ]; then
    logStdout "All servers successfully updated."
    UPDATE_ERROR=0
    return 0
  fi
  if [ ${COUNT_SERVERS_SUCCESSFULL} -eq 0 ]; then
    logStderr "No server updated."
    UPDATE_ERROR=1
    return 2
  fi

  logStderr "${COUNT_SERVERS_SUCCESSFULL} of ${COUNT_SERVERS} servers successfully updated."
  UPDATE_ERROR=1
  return 1
}

# update entry (add or remove)
update() {
  [ ${ADD:-0} -eq 1 ] && addEntry
  [ ${REMOVE:-0} -eq 1 ] && removeEntry
}

# remove entry
removeEntry() {
  local COMMAND

  # Delete entries in forward zone
  COMMAND="update delete ${NAME}.${DOMAIN} A"
  updateDnsEntry remove "${DOMAIN}" "${COMMAND}"

  # Delete entries in reverse non-static zone
  COMMAND="update delete $(getReverseEntry) PTR"
  updateDnsEntry remove "$(getReverseZone)" "${COMMAND}"
}

# add entry
addEntry() {
  local COMMAND
  
  # Delete and add entries in forward zone
  COMMAND="update delete ${NAME}.${DOMAIN} A\n"
  COMMAND="${COMMAND}update add ${NAME}.${DOMAIN} ${TTL} A ${IPADDRESS}"
  updateDnsEntry add "${DOMAIN}" "${COMMAND}"

  # Delete and add entries in reverse zone
  COMMAND="update delete $(getReverseEntry) PTR\n"
  COMMAND="${COMMAND}update add $(getReverseEntry) ${TTL} PTR ${NAME}.${DOMAIN}"
  updateDnsEntry add "$(getReverseZone)" "${COMMAND}"
}

while getopts ":adi:n:hq" opt; do
  case $opt in
    a) ADD=1
       ;;
    d) REMOVE=1
       ;;
    i) IPADDRESS="${OPTARG}"
       ;;
    n) NAME=$(echo "${OPTARG}" | tr '[:upper:]' '[:lower:]')
       ;;
    q) QUIET=1
       ;;
    h) printUsage
       exit 255
       ;;
#    \?) echo "Invalid option: -$OPTARG" >&2
#       printUsage
#       exit 255
#       ;;
  esac
done

checkParameters
update
exit ${UPDATE_ERROR}
