#!/usr/bin/env bash
set -eo pipefail
echo "Preparing Web Server TLS Certificates"

# Global variable defaults
IGNITION_DATA_DIR="/data"
WEB_TLS_SECRETS_DIR="/run/secrets/web-tls"
SSL_PFX_ALIAS="ignition"
SSL_PFX_PASSPHRASE="ignition"

###############################################################################
# Places the Web Server TLS Keystore
###############################################################################
function main() {
  # Update alias in the inbound Web Server PKCS#12 keystore and put into place
  populateWebKeystore
}

###############################################################################
# Places the Web Server TLS Keystore
###############################################################################
function populateWebKeystore() {
  local existing_alias
  local target_alias
  local keystore_parent_path="${IGNITION_DATA_DIR}/local"
  local keystore_path="${keystore_parent_path}/ssl.pfx"

  info "Populating Web Server TLS Keystore -> ${keystore_path}"

  # Replace any existing TLS keystore with the updated one from the mounted secret
  rm -v -f "${keystore_path}"
  cp -v "${WEB_TLS_SECRETS_DIR}/keystore.p12" "${keystore_path}"

  # Modify the TLS keystore to use the alias "ignition" to align with Ignition defaults
  existing_alias=$(keytool -list -keystore "${keystore_path}" -storepass "${SSL_PFX_PASSPHRASE}" | grep PrivateKeyEntry | cut -d, -f 1)
  target_alias="${SSL_PFX_ALIAS}"
  if [ "${existing_alias}" != "${target_alias}" ]; then
    info "Updating Web Server TLS Keystore alias from '${existing_alias}' to '${target_alias}'"
    keytool -changealias -alias "${existing_alias}" -destalias "${target_alias}" \
      -keystore "${keystore_path}" -storepass "${SSL_PFX_PASSPHRASE}"
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
  >&2 echo "Usage: $0 -a <alias> -s <path/to/tls/secret> -d <path/to/data/folder> [-h] [-v]"
  >&2 echo "  -a <alias> - The alias to use for the webserver TLS keystore (default: ${SSL_PFX_ALIAS})"
  >&2 echo "  -s <path/to/gan/secret> - The path to the mounted secret containing the webserver TLS certs/keystore (default: ${WEB_TLS_SECRETS_DIR})"
  >&2 echo "  -d <path/to/data/folder> - The path to the Ignition data folder (default: ${IGNITION_DATA_DIR})"
  >&2 echo "  -h - Print this help message"
  >&2 echo "  -v - Enable verbose output"
}

# Argument Processing
while getopts ":hva:s:d:" opt; do
  case "$opt" in
  v)
    verbose=1
    ;;
  a)
    SSL_PFX_ALIAS="${OPTARG}"
    ;;
  s)
    WEB_TLS_SECRETS_DIR="${OPTARG}"
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
if [ ! -f "${WEB_TLS_SECRETS_DIR}/keystore.p12" ]; then
  >&2 echo "ERROR: Web TLS Keystore not found at ${WEB_TLS_SECRETS_DIR}/keystore.p12"
  usage
  exit 1
fi

if [ ! -d "${IGNITION_DATA_DIR}" ]; then
  >&2 echo "ERROR: Ignition Data Directory not found at ${IGNITION_DATA_DIR}"
  usage
  exit 1
fi

main
