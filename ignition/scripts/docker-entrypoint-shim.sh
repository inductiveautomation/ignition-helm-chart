#!/usr/bin/env bash
set -eo pipefail

# Local variable/constant declarations
readonly entrypoint_log_datefmt="%(%Y/%m/%d %H:%M:%S)T"
readonly entrypoint_log_prefix="init     | ${entrypoint_log_datefmt} |"

# Global variable defaults
declare IGNITION_MODULES_LOCATION="${IGNITION_MODULES_LOCATION:-${IGNITION_INSTALL_LOCATION:?undefined location}/user-lib/modules}"
declare EXTERNAL_MODULES_LOCATION="${EXTERNAL_MODULES_LOCATION:-/media/shared-files/modules}"
declare IGNITION_HELM_LOAD_EXTERNAL_MODULES="${IGNITION_HELM_LOAD_EXTERNAL_MODULES:-false}"
declare IGNITION_HELM_LOAD_EXTERNAL_MODULES_REPLACE="${IGNITION_HELM_LOAD_EXTERNAL_MODULES_REPLACE:-false}"
declare IGNITION_DOCKER_ENTRYPOINT="${IGNITION_DOCKER_ENTRYPOINT:-/usr/local/bin/docker-entrypoint.sh}"

###############################################################################
# Main function
###############################################################################
function main() {
  if [ "${IGNITION_HELM_LOAD_EXTERNAL_MODULES}" == "true" ]; then
    loadExternalModules
  fi

  exec "${IGNITION_DOCKER_ENTRYPOINT}" "$@"
}

###############################################################################
# Load External Modules into Ignition Installation
###############################################################################
function loadExternalModules() {
  local source_module dest_module
  local -a cp_args=( "cp" "-v" )
  shopt -s nullglob
  local -a source_modules=( "${EXTERNAL_MODULES_LOCATION}"/*.modl )
  shopt -u nullglob

  if [ ${#source_modules[@]} -eq 0 ]; then
    debug "No external modules found in ${EXTERNAL_MODULES_LOCATION}"
    return
  fi

  # if replace existing is set, add `-f` to cp_args
  if [ "${IGNITION_HELM_LOAD_EXTERNAL_MODULES_REPLACE}" == "true" ]; then
    cp_args+=( -f )
  fi

  info "Loading external modules from ${EXTERNAL_MODULES_LOCATION}"
  for source_module in "${source_modules[@]}"; do
    dest_module="${IGNITION_MODULES_LOCATION}/$(basename "${source_module}")"
    if [ -f "${dest_module}" ]; then
      if [ "${IGNITION_HELM_LOAD_EXTERNAL_MODULES_REPLACE}" = "true" ]; then
        debug "Replacing existing module: ${dest_module}"
      else
        debug "Skipping existing in-place module: ${dest_module}"
      fi
      continue
    fi

    "${cp_args[@]}" "${source_module}" "${dest_module}"
  done
}

###############################################################################
# Alias for printing to console/stdout
# Arguments:
#   <...> Content to print
###############################################################################
function info() {
  readarray -t message_arr <<< "${*}"
  for message_line in "${message_arr[@]}"; do
    printf "${entrypoint_log_prefix} %s\n" "$(date +%s)" "${message_line}"
  done
}

###############################################################################
# Alias for printing to stderr
# Arguments:
#   -r Use short prefix
#   -n Skip immediate exit of entire script
#   <...> Content to print
###############################################################################
function error() {
  local prefix="${entrypoint_log_prefix} ERROR:"
  local exit_code=1
  local OPTIND
  while getopts ":rn" opt; do
    # shellcheck disable=SC2220
    case "${opt}" in
      r) # raw mode, use short prefix
        prefix="${entrypoint_log_prefix}"
        ;;
      n) # don't send exit code, must manually exit
        exit_code=0
        ;;
    esac
  done
  shift $((OPTIND-1))

  message="$*"
  printf "${prefix} %s\n" "$(date +%s)" "${message}" 1>&2
  if [[ ${exit_code} -gt 0 ]]; then
    exit ${exit_code}
  fi
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

# Piggy-back off of entrypoint debug var
[ "${ENTRYPOINT_DEBUG_ENABLED:-}" == "true" ] && verbose=1

# Perform checks
if [ ! -d "${IGNITION_MODULES_LOCATION}" ]; then
  >&2 echo "ERROR: Ignition Modules Directory not found at ${IGNITION_MODULES_LOCATION}"
  exit 1
fi

# Pre-create the external modules location if it does not exist
if [ "${IGNITION_HELM_LOAD_EXTERNAL_MODULES}" == "true" ] && [ ! -d "${EXTERNAL_MODULES_LOCATION}" ]; then
  mkdir -p "${EXTERNAL_MODULES_LOCATION}"
  info "Created external modules directory at ${EXTERNAL_MODULES_LOCATION}"
fi

main "$@"
