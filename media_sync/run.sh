#!/usr/bin/with-contenv bashio
# Translate the app options into the environment media-sync.sh expects,
# then run it once and exit.
set -eo pipefail

STATE_DIR="/config/media_sync"
REQUEST_FILE="${STATE_DIR}/request.json"
LOG_FILE="${STATE_DIR}/media-sync.log"
KEY_DIR="/ssl/media_sync"
KEY_FILE="${KEY_DIR}/remote.key"
SCRIPT_DIR="/config/scripts"
SCRIPT_COPY="${SCRIPT_DIR}/media-sync.sh"

# The shared log lives in /config, which is included in backups, so keep it
# bounded. The app is one-shot, so recent activity is replayed into this run's
# output before starting - that way the Log tab shows how we got here.
LOG_MAX_LINES=2000
LOG_HISTORY_LINES=50

mkdir -p "${STATE_DIR}" "${KEY_DIR}" "${SCRIPT_DIR}"

bashio::log.level "$(bashio::config 'log_level')"

log_line() {
  printf '%s  %-7s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >> "${LOG_FILE}"
}

if [ -f "${LOG_FILE}" ]; then
  if [ "$(wc -l < "${LOG_FILE}")" -gt "${LOG_MAX_LINES}" ]; then
    tail -n "${LOG_MAX_LINES}" "${LOG_FILE}" > "${LOG_FILE}.trimmed"
    mv "${LOG_FILE}.trimmed" "${LOG_FILE}"
  fi
  echo "----- recent activity -------------------------------------------"
  tail -n "${LOG_HISTORY_LINES}" "${LOG_FILE}"
  echo "----- this run --------------------------------------------------"
fi

# Keep a runnable copy where users can reach it. It is refreshed on every
# start so it never drifts from the version the app itself runs.
if ! cmp -s /media-sync.sh "${SCRIPT_COPY}"; then
  cp /media-sync.sh "${SCRIPT_COPY}"
  chmod +x "${SCRIPT_COPY}"
  bashio::log.info "Refreshed ${SCRIPT_COPY}"
  log_line "app" "refreshed ${SCRIPT_COPY}"
fi

if ! bashio::fs.file_exists "${KEY_FILE}"; then
  bashio::log.warning "No SSH key yet, generating one at ${KEY_FILE}"
  ssh-keygen -t ed25519 -N "" -f "${KEY_FILE}" -C "media-sync" >/dev/null
  bashio::log.warning "Install this public key on the remote server, then start the app again:"
  bashio::log.warning "$(cat "${KEY_FILE}.pub")"
  log_line "app" "generated a new SSH key at ${KEY_FILE}"
fi
chmod 600 "${KEY_FILE}"

export VERBOSITY="$(bashio::config 'sync_log_verbosity')"
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

# The settings switch wins over anything Home Assistant asked for. It is a
# safety catch, so it has to be impossible to override by accident.
if bashio::config.true 'dry_run'; then
  case "${args}" in
    *--dry-run*) ;;
    *)           args="${args} --dry-run" ;;
  esac
  bashio::log.warning "Dry run is switched on in the settings - nothing will be written."
  log_line "app" "dry run is on in the settings, this run changes nothing"
fi

bashio::log.info "Running media sync ${args:-(full bidirectional run)}"
log_line "run" "started ${args:-(both directions)}"

# tee so the run appears both in the Log tab and in the shared log
status=0
/media-sync.sh --no-hop ${args} 2>&1 | tee -a "${LOG_FILE}" || status=$?

if [ "${status}" -eq 0 ]; then
  log_line "run" "finished"
else
  log_line "run" "failed (exit ${status})"
fi

exit "${status}"
