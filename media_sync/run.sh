#!/usr/bin/with-contenv bashio
# Translate the app options into the environment media-sync.sh expects,
# then run it once and exit.
set -e

STATE_DIR="/config/media_sync"
REQUEST_FILE="${STATE_DIR}/request.json"
KEY_DIR="/ssl/media_sync"
KEY_FILE="${KEY_DIR}/remote.key"

mkdir -p "${STATE_DIR}" "${KEY_DIR}"

if ! bashio::fs.file_exists "${KEY_FILE}"; then
  bashio::log.warning "No SSH key yet, generating one at ${KEY_FILE}"
  ssh-keygen -t ed25519 -N "" -f "${KEY_FILE}" -C "media-sync" >/dev/null
  bashio::log.warning "Install this public key on the remote server, then start the app again:"
  bashio::log.warning "$(cat "${KEY_FILE}.pub")"
fi
chmod 600 "${KEY_FILE}"

export REMOTE_HOST="$(bashio::config 'remote_host')"
export REMOTE_USER="$(bashio::config 'remote_user')"
export REMOTE_PORT="$(bashio::config 'remote_port')"
export REMOTE_BASE="$(bashio::config 'remote_base')"
export REMOTE_KEY="${KEY_FILE}"
export KNOWN_HOSTS="${KEY_DIR}/known_hosts"
export STATE_FILE="${STATE_DIR}/state.json"
export DELETE_REPORT="${STATE_DIR}/deletions.txt"

pairs=""
for index in $(bashio::config 'folders|keys'); do
  pairs="${pairs}$(bashio::config "folders[${index}].name")|$(bashio::config "folders[${index}].remote")|$(bashio::config "folders[${index}].local")|$(bashio::config "folders[${index}].exclude" '')
"
done
export SYNC_PAIRS="${pairs}"

includes=""
for index in $(bashio::config 'include_dirs|keys'); do
  includes="${includes}$(bashio::config "include_dirs[${index}]")
"
done
export INCLUDE_DIRS="${includes}"

excludes=""
for index in $(bashio::config 'exclude_patterns|keys'); do
  excludes="${excludes}$(bashio::config "exclude_patterns[${index}]")
"
done
export EXCLUDE_PATTERNS="${excludes}"

case "$(bashio::config 'direction')" in
  pull) args="--pull-only" ;;
  push) args="--push-only" ;;
  *)    args="" ;;
esac

# Home Assistant leaves the arguments for this run in a request file.
if bashio::fs.file_exists "${REQUEST_FILE}"; then
  requested="$(jq -r '.args // [] | join(" ")' "${REQUEST_FILE}")"
  rm -f "${REQUEST_FILE}"
  case "${requested}" in
    *--pull-only*|*--push-only*) args="${requested}" ;;
    *)                           args="${args} ${requested}" ;;
  esac
fi

bashio::log.info "Running media sync ${args:-(full bidirectional run)}"
exec /media-sync.sh --no-hop ${args}
