#!/usr/bin/env bash
set -eo pipefail

# Global Variable Defaults
IGNITION_DATA_DIR="/data"
IGNITION_SRC_DATA_DIR="${IGNITION_INSTALL_LOCATION}/data"

###############################################################################
# Initializes the Ignition data volume with default files from the image
###############################################################################
function main() {
  local seed_file="${IGNITION_DATA_DIR}/.ignition-seed-complete"
  local src_dir="${IGNITION_SRC_DATA_DIR}"

  if [ ! -f "${seed_file}" ]; then
    touch "${seed_file}"
    if [ -d "${src_dir}_clean" ]; then
      src_dir="${src_dir}_clean"
    fi
    info "Seeding Ignition Data Volume from image source: ${src_dir}"
    cp -dpR "${src_dir}"/* "${IGNITION_DATA_DIR}"/
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
  >&2 echo "Usage: $0 -d <path/to/data/folder>"
  >&2 echo "  -d <path/to/data/folder> - The path to the Ignition data folder (default: ${IGNITION_DATA_DIR})"
  >&2 echo "  -h - Print this help message"
  >&2 echo "  -v - Enable verbose output"
}

# Argument Processing
while getopts ":hvd:" opt; do
  case "$opt" in
  v)
    verbose=1
    ;;
  d)
    IGNITION_DATA_DIR="${OPTARG}"
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

# Perform argument checks
if [ ! -d "${IGNITION_DATA_DIR}" ]; then
  >&2 echo "ERROR: Ignition Data Directory not found at ${IGNITION_DATA_DIR}"
  usage
  exit 1
fi

main
