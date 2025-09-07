#!/usr/bin/env bash
set -eo pipefail

# Check for minimum of bash 4
if [ "${BASH_VERSINFO:-0}" -lt 4 ]; then
  echo "ERROR: bash version 4 or higher is required for this script, found version ${BASH_VERSINFO[0]}" >&2
  exit 1
fi

# Global variable defaults
port=${GATEWAY_HTTP_PORT:-8088}
status_endpoint="http://localhost:${port}/system/gwinfo"
timeout_secs=3
expected_context_state=RUNNING
expected_redundant_state=Good

###############################################################################
# Invoke a Redundancy-aware Health Check
###############################################################################
function main() {
  if [ ! -x "$(command -v curl)" ]; then
    echo "ERROR: curl is required for this health check" >&2
    exit 1
  fi

  debug "Status endpoint: ${status_endpoint}, expecting context state: ${expected_context_state}, expecting redundant state: ${expected_redundant_state}, timeout: ${timeout_secs}."

  curl_output=$(curl -s --max-time "${timeout_secs}" -L -k -f "${status_endpoint}" 2>&1)

  debug "curl output: ${curl_output}"

  # Gather the fields from gwinfo into an associative array
  IFS=';' read -ra gwinfo_fields_raw <<< "$curl_output"
  declare -A gwinfo_fields=( )
  for field in "${gwinfo_fields_raw[@]}"; do
    IFS='=' read -ra field_parts <<< "$field"
    gwinfo_fields[${field_parts[0]}]=${field_parts[1]}
  done

  # Check ContextStatus and RedundantState fields and exit if no match
  if [ "${gwinfo_fields[ContextStatus]}" != "${expected_context_state}" ]; then
    if [ "${gwinfo_fields[ContextStatus]}" != "NEEDS_COMMISSIONING" ]; then
      echo "FAILED: ContextStatus is ${gwinfo_fields[ContextStatus]}, expected ${expected_context_state}" >&2
      exit 1
    fi
  elif [ "${gwinfo_fields[RedundantState]}" != "${expected_redundant_state}" ]; then
    # Check RedundantNodeActiveStatus field
    if [ "${gwinfo_fields[RedundantNodeActiveStatus]}" != "Active" ]; then
      echo "FAILED: Not Active and RedundantState is ${gwinfo_fields[RedundantState]}, expected ${expected_redundant_state}" >&2
      exit 1
    fi
  fi
  debug "SUCCESS"
  exit 0
}

###############################################################################
# Outputs to stderr
###############################################################################
function debug() {
  # shellcheck disable=SC2236
  if [ ! -z ${verbose+x} ]; then
    echo "DEBUG: $*"
  fi
}

###############################################################################
# Print usage information
###############################################################################
function usage() {
# usage redundant-health-check.sh 
  >&2 echo "Usage: $0 [flags] STATUS_ENDPOINT"
  >&2 echo "Example: ./redundant-health-check.sh -r Good -s RUNNING http://localhost:8088/system/gwinfo"
  >&2 echo "Flags:"
  >&2 echo "  -r <state> - Expected redundant state (default: Good)"
  >&2 echo "  -s <path/to/gan/secret> - The path to the mounted secret containing the webserver TLS certs/keystore (default: ${WEB_TLS_SECRETS_DIR})"
  >&2 echo "  -d <path/to/data/folder> - The path to the Ignition data folder (default: ${IGNITION_DATA_DIR})"
  >&2 echo "  -h - Print this help message"
  >&2 echo "  -v - Enable verbose output"
}

# Argument Processing
while getopts ":hvr:s:t:" opt; do
  case "$opt" in
  v)
    verbose=1
    ;;
  r)
    expected_redundant_state=${OPTARG}
    ;;
  s)
    expected_context_state=${OPTARG}
    ;;
  t)
    timeout_secs=${OPTARG}
    if ! [[ ${timeout_secs} =~ ^[0-9]+$ ]]; then
      echo "ERROR: timeout requires a number" >&2
      exit 1
    fi
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

# evaluate remaining positional args, if present
if [ -n "$1" ]; then
  status_endpoint="$1"
fi

# pre-processing done, proceed with main call
main
