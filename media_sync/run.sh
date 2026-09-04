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
LOG_HISTORY_LINES=50
LOG_MAX_BYTES=1048576

mkdir -p "${STATE_DIR}" "${KEY_DIR}" "${SCRIPT_DIR}"

bashio::log.level "$(bashio::config 'advanced.log_level')"

log_line() {
  printf '%s  %-7s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2" >> "${LOG_FILE}"
}

prune_log() {
  [ -f "${LOG_FILE}" ] || return 0

  _keep_days="$(bashio::config 'advanced.log_keep_days')"
  case "${_keep_days}" in
    ''|*[!0-9]*) _keep_days=14 ;;
  esac

  # GNU date syntax is not available here, so work the cutoff out from epoch
  # seconds and format it back.
  _cutoff_epoch=$(( $(date -u +%s) - _keep_days * 86400 ))
  _cutoff="$(date -u -d "@${_cutoff_epoch}" '+%Y-%m-%d' 2>/dev/null \
             || date -u -r "${_cutoff_epoch}" '+%Y-%m-%d' 2>/dev/null || true)"

  if [ -n "${_cutoff}" ]; then
    # Indented lines carry no date of their own; they belong to the entry
    # above, so the keep decision carries forward across them.
    if awk -v cutoff="${_cutoff}" '
          /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] / { keep = (substr($0, 1, 10) >= cutoff) }
          keep
        ' "${LOG_FILE}" > "${LOG_FILE}.pruned"; then
      mv "${LOG_FILE}.pruned" "${LOG_FILE}"
    else
      rm -f "${LOG_FILE}.pruned"
      bashio::log.warning "Could not prune the log; keeping it as it is."
    fi
  else
    bashio::log.warning "Could not work out the log cutoff date; keeping the log as it is."
  fi

  # Days alone do not bound one very noisy run, so cap the size as a backstop.
  if [ "$(wc -c < "${LOG_FILE}")" -gt "${LOG_MAX_BYTES}" ]; then
    mv "${LOG_FILE}" "${LOG_FILE}.1"
    bashio::log.warning "Log passed $((LOG_MAX_BYTES / 1024))KB - earlier entries moved aside to media-sync.log.1"
  fi
}

prune_log

if [ -f "${LOG_FILE}" ]; then
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

export PROTOCOL="$(bashio::config 'source.protocol' | tr 'A-Z' 'a-z')"

# The SSH key is only meaningful for the ssh transport. Generating one for a
# WebDAV setup would print a key nobody has anywhere to put.
if [ "${PROTOCOL}" = "ssh" ]; then
  if ! bashio::fs.file_exists "${KEY_FILE}"; then
    bashio::log.warning "No SSH key yet, generating one at ${KEY_FILE}"
    ssh-keygen -t ed25519 -N "" -f "${KEY_FILE}" -C "media-sync" >/dev/null
    bashio::log.warning "Install this public key on the remote server, then start the app again:"
    bashio::log.warning "$(cat "${KEY_FILE}.pub")"
    log_line "app" "generated a new SSH key at ${KEY_FILE}"
  fi
  chmod 600 "${KEY_FILE}"
fi

export VERBOSITY="$(bashio::config 'advanced.sync_log_verbosity')"
export WEBDAV_PARALLEL="$(bashio::config 'advanced.webdav_parallel')"
if bashio::config.true 'advanced.skip_unchanged'; then
  export SKIP_UNCHANGED=1
else
  export SKIP_UNCHANGED=0
fi
export CHANGE_DEPTH="$(bashio::config 'advanced.change_depth')"
export REMOTE_HOST="$(bashio::config 'ssh.host')"
export REMOTE_USER="$(bashio::config 'ssh.user')"
export REMOTE_PORT="$(bashio::config 'ssh.port')"
export REMOTE_BASE="$(bashio::config 'source.remote_base')"
export REMOTE_KEY="${KEY_FILE}"
export WEBDAV_URL="$(bashio::config 'webdav.url')"
export WEBDAV_USER="$(bashio::config 'webdav.user')"
export WEBDAV_PASS="$(bashio::config 'webdav.password')"
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
for index in $(bashio::config 'sync.include_dirs|keys'); do
  includes="${includes}$(bashio::config "sync.include_dirs[${index}]")
"
done
export INCLUDE_DIRS="${includes}"

excludes=""
for index in $(bashio::config 'sync.exclude_patterns|keys'); do
  excludes="${excludes}$(bashio::config "sync.exclude_patterns[${index}]")
"
done
export EXCLUDE_PATTERNS="${excludes}"

case "$(bashio::config 'sync.direction')" in
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

# Deletion protection is on unless the user has deliberately turned it off.
# Off means every run deletes as it goes, with no confirmation step.
if ! bashio::config.true 'sync.delete_protection'; then
  case "${args}" in
    *--yes*) ;;
    *)       args="${args} --yes" ;;
  esac
  bashio::log.warning "Deletion protection is OFF - anything missing on one side will be deleted on the other."
  log_line "app" "deletion protection is off, this run deletes as it goes"
fi

if bashio::config.true 'sync.force_removal'; then
  case "${args}" in
    *--force-removal*) ;;
    *)                 args="${args} --force-removal" ;;
  esac
  log_line "app" "leftover folders will be removed when a deletion is confirmed"
fi

# The settings switch wins over anything Home Assistant asked for. It is a
# safety catch, so it has to be impossible to override by accident.
if bashio::config.true 'sync.dry_run'; then
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
