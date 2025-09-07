#!/usr/bin/env bash
set -eo pipefail

EXEC_FINAL=0

###############################################################################
# Main function evaluates arguments in sequence.  The last argument may optionally be invoked 
# with `exec` if the `-e` flag is provided.  Use this for launching Ignition, for example.
###############################################################################
function main() {
  arg_count=$#
  for (( i=1; i<=$((arg_count-1)); i++ )); do
    # shellcheck disable=SC2294
    eval "${@:$i:1}"
  done

  if [ "$EXEC_FINAL" -eq 0 ]; then
    # shellcheck disable=SC2294
    eval "${@:$i:1}"
  else
    read -r -a final_arg <<< "${@:$i:1}"
    exec "${final_arg[@]}"
  fi
}

# Argument Processing
while getopts ":e" opt; do
  case "$opt" in
  e)
    EXEC_FINAL=1
    ;;
  \?)
    echo "Invalid option: -${OPTARG}" >&2
    exit 1
    ;;
  :)
    echo "Invalid option: -${OPTARG} requires an argument" >&2
    exit 1
    ;;
  esac
done

# shift positional args based on number consumed by getopts
shift $((OPTIND-1))

main "$@"