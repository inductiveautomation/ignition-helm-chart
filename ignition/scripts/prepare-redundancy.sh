#!/usr/bin/env bash
set -eo pipefail
echo "Preparing Redundancy Settings"

# Global variable defaults
declare IGNITION_DATA_DIR="/data"
declare GLOBAL_COUNTER=0
declare ENABLE_REDUNDANCY_LICENSING=false
declare REDUNDANCY_ROLE=""
declare REDUNDANCY_BASE_FILE="/config/files/redundancy-base.xml"
declare REDUNDANCY_ENABLE_TLS="true"

# Undefined global variables
declare REDUNDANCY_PRIMARY_HOST
declare REDUNDANCY_PRIMARY_PORT

###############################################################################
# Main function
###############################################################################
function main() {
  if [[ "${HOSTNAME}" =~ -([0-9])$ ]]; then
    case "${BASH_REMATCH[1]}" in
      0)
        REDUNDANCY_ROLE="primary"
        ;;
      1)
        REDUNDANCY_ROLE="backup"
        ;;
      *)
        info "Unknown Redundancy Hostname Suffix: ${HOSTNAME}"
        exit 1
        ;;
    esac
  fi

  preparePublicAddress
  prepareRedundancyLicensing
  seedRedundancy
}

###############################################################################
# Seed redundancy settings
###############################################################################
function seedRedundancy() {
  local redundancy_xml_file="${IGNITION_DATA_DIR}/redundancy.xml"
  local redundancy_role="${REDUNDANCY_ROLE^}"
  
  if [ "${redundancy_role}" == "Primary" ]; then
    # Update role definition for compatibility
    redundancy_role="Master"
  fi

  if [ ! -f "${redundancy_xml_file}" ]; then
    info "Seeding Redundancy configuration file"
    cp -v "${REDUNDANCY_BASE_FILE}" "${IGNITION_DATA_DIR}/redundancy.xml"
  fi

  info "Initializing Redundancy as ${redundancy_role} role"
  addToXml -d "redundancy.noderole" "${redundancy_role}" "${redundancy_xml_file}"

  info "Configuring Redundancy Primary host: ${REDUNDANCY_PRIMARY_HOST}"
  addToXml "redundancy.gan.host" "REDUNDANCY_PRIMARY_HOST" "${redundancy_xml_file}"

  info "Configuring Redundancy Primary port: ${REDUNDANCY_PRIMARY_PORT}"
  addToXml "redundancy.gan.port" "REDUNDANCY_PRIMARY_PORT" "${redundancy_xml_file}"

  info "Configuring Redundancy TLS: ${REDUNDANCY_ENABLE_TLS}"
  addToXml "redundancy.gan.enableSsl" "REDUNDANCY_ENABLE_TLS" "${redundancy_xml_file}"
}

###############################################################################
# Updates gateway.xml with Public Address settings based on env vars
###############################################################################
function preparePublicAddress() {
  local -a public_address_vars=(
    "GATEWAY_PUBLIC_ADDRESS"
  )
  local -a public_http_vars=(
    "GATEWAY_PUBLIC_HTTP_PORT"
  )
  local -a public_https_vars=(
    "GATEWAY_PUBLIC_HTTPS_PORT"
  )
  local gateway_xml_file
  
  info "Preparing Public Address settings for ${REDUNDANCY_ROLE^} Gateway"

  public_address_vars+=( "GATEWAY_PUBLIC_ADDRESS_${REDUNDANCY_ROLE^^}" )
  public_http_vars+=( "GATEWAY_PUBLIC_HTTP_PORT_${REDUNDANCY_ROLE^^}" )
  public_https_vars+=( "GATEWAY_PUBLIC_HTTPS_PORT_${REDUNDANCY_ROLE^^}" )

  # Search for gateway.xml file, falling back to the clean/seed file
  if [ -f "${IGNITION_DATA_DIR}/gateway.xml" ]; then
    gateway_xml_file="${IGNITION_DATA_DIR}/gateway.xml"
  elif [ -f "${IGNITION_DATA_DIR}/gateway.xml_clean" ]; then
    gateway_xml_file="${IGNITION_DATA_DIR}/gateway.xml_clean"
  else
    >&2 echo "ERROR: Ignition Gateway XML could not be located under '${IGNITION_DATA_DIR}'"
    exit 1
  fi

  # Update gateway.xml with public address settings
  for var in "${public_address_vars[@]}"; do
    addToXml gateway.publicAddress.address "${var}" "${gateway_xml_file}"
  done
  for var in "${public_http_vars[@]}"; do
    addToXml gateway.publicAddress.httpPort "${var}" "${gateway_xml_file}"
  done
  for var in "${public_https_vars[@]}"; do
    addToXml gateway.publicAddress.httpsPort "${var}" "${gateway_xml_file}"
  done

  # if we had any matches during XML processing, mark autoDetect false
  if (( GLOBAL_COUNTER > 0 )); then
    addToXml -d gateway.publicAddress.autoDetect "false" "${gateway_xml_file}"
  fi
}

###############################################################################
# Prepare a symlink for licensing by-redundancy role
###############################################################################
function prepareRedundancyLicensing() {
  if [ "${ENABLE_REDUNDANCY_LICENSING}" != "true" ]; then
    return
  fi

  # if there is a secret at /run/secrets/ignition-license-key, link it
  info "Linking license key for ${REDUNDANCY_ROLE,,} redundancy role"
  ln -sf "/run/secrets/ignition/${REDUNDANCY_ROLE,,}-ignition-license-key" "${IGNITION_DATA_DIR}/local/.ignition-license-key"
  info "Linking activation token for ${REDUNDANCY_ROLE,,} redundancy role"
  ln -sf "/run/secrets/ignition/${REDUNDANCY_ROLE,,}-ignition-activation-token" "${IGNITION_DATA_DIR}/local/.ignition-activation-token"
}

###############################################################################
# Adds entries to gateway.xml if the supplied ENV_VAR_NAME is defined or VALUE
# if in direct mode (-d).
# Arguments:
#   [-d], KEY, ENV_VAR_NAME|VALUE, FILE
# Usage:
#   addToXml gateway.publicAddress.address httpAddress data/gateway.xml
#   addToXml -d gateway.publicAddress.autoDetect "false" data/gateway.xml
###############################################################################
function addToXml() {
  local OPTIND key val xml_file mode="indirect"

  while getopts ":d" opt; do
    # shellcheck disable=SC2220
    case "${opt}" in
      d) # direct mode, use
        mode="direct"
        ;;
    esac
  done
  shift $((OPTIND-1))

  key="${1}"
  case "${mode}" in
    direct)
      val="${2}"
      ;;
    indirect)
      val=${!2:-}
      ;;
    *)
      error "Unexpected mode in addToXml, aborting..."
      ;;
  esac

  xml_file="${3}"
  if [[ -n "${val}" ]]; then  
    # Use xmlstarlet to "upsert" the target element
    debug "Setting '${key}' to '${val}' in file '${xml_file}'"
    xmlstarlet ed --inplace \
      -u "/properties/entry[@key='${key}']" -v "${val}" \
      -s "/properties" -t elem -n entry -v "${val}" \
      -i "/properties/entry[count(@*)=0]" -t attr -n key -v "${key}" \
      -d "/properties/entry[@key='${key}'][position() > 1]" \
      "${xml_file}"
    GLOBAL_COUNTER=$((GLOBAL_COUNTER+1))
  else
    debug "Skipping '${key}' in ${mode} mode with raw value '${2}' in file '${xml_file}'"
  fi
}

###############################################################################
# Alias for printing to console/stdout
# Arguments:
#   <...> Content to print
###############################################################################
function info() {
  readarray -t message_arr <<< "${*}"
  for message_line in "${message_arr[@]}"; do
    printf "%s\n" "${message_line}"
  done
}

###############################################################################
# Outputs to stderr
###############################################################################
function debug() {
  # shellcheck disable=SC2236
  if [ ! -z ${verbose+x} ]; then
    >&2 echo "  DEBUG: $*"
  fi
}

###############################################################################
# Print usage information
###############################################################################
function usage() {
  >&2 echo "Usage: $0 -d <path/to/data/folder> -g <primary_hostname> [-p <port>] [-c <path/to/redundancy-base.xml>] [-k] [-l] [-h] [-v]"
  >&2 echo "  -d <path/to/data/folder> - The path to the Ignition data folder (default: ${IGNITION_DATA_DIR})"
  >&2 echo "  -g - The hostname of the primary gateway (for redundancy GAN connection setup)"
  >&2 echo "  -p - The port of the primary gateway (defaults, unless overridden: 8060, or 8088 for insecure mode)"
  >&2 echo "  -k - Insecure Mode, use port 8088 and no TLS (default: false)"
  >&2 echo "  -c - Path to a seed file for redundancy (default: /config/files/redundancy-base.xml)"
  >&2 echo "  -l - Perform licensing preparation"
  >&2 echo "  -h - Print this help message"
  >&2 echo "  -v - Enable verbose output"
}

# Argument Processing
while getopts ":hlkvc:d:g:p:" opt; do
  case "$opt" in
  v)
    verbose=1
    ;;
  d)
    IGNITION_DATA_DIR="${OPTARG}"
    ;;
  g)
    REDUNDANCY_PRIMARY_HOST="${OPTARG}"
    ;;
  p)
    REDUNDANCY_PRIMARY_PORT="${OPTARG}"
    ;;
  k)
    REDUNDANCY_ENABLE_TLS="false"
    ;;
  c)
    REDUNDANCY_BASE_FILE="${OPTARG}"
    ;;
  l)
    ENABLE_REDUNDANCY_LICENSING=true
    ;;
  h)
    usage
    exit 0
    ;;
  \?)
    usage
    echo "Invalid option: -${OPTARG}" >&2
    exit 1
    ;;
  :)
    usage
    echo "Invalid option: -${OPTARG} requires an argument" >&2
    exit 1
    ;;
  esac
done

# shift positional args based on number consumed by getopts
shift $((OPTIND-1))

# Configure defaults
if [ -z "${REDUNDANCY_PRIMARY_PORT}" ]; then
  if [[ "${REDUNDANCY_ENABLE_TLS}" == "true" ]]; then
    REDUNDANCY_PRIMARY_PORT="8060"
  else
    REDUNDANCY_PRIMARY_PORT="8088"
  fi
fi

# Perform argument checks
if [ ! -d "${IGNITION_DATA_DIR}" ]; then
  >&2 echo "ERROR: Ignition Data Directory not found at ${IGNITION_DATA_DIR}"
  usage
  exit 1
fi
if [ ! -f "${REDUNDANCY_BASE_FILE}" ]; then
  >&2 echo "ERROR: Redundancy Base File not found at ${REDUNDANCY_BASE_FILE}"
  usage
  exit 1
fi
if [ -z "${REDUNDANCY_PRIMARY_HOST}" ]; then
  >&2 echo "ERROR: Primary Gateway Hostname not provided"
  usage
  exit 1
fi

main
