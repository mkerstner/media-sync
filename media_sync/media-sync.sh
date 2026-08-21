#!/bin/sh
# media-sync.sh
#
# Keeps a remote server and the local media library in sync, in both directions.
#
# Part of the Media Sync app for Home Assistant.
# Documentation and source: https://github.com/mkerstner/media-sync
#
# DO NOT EDIT THIS COPY. The app rewrites /config/scripts/media-sync.sh every
# time it starts, so any change you make here is lost on the next run. Copy it
# under another name first if you want to customise it.
#
# Every setting below can be overridden from the environment, which is how the
# Media Sync app passes its options in. Run standalone and the defaults apply,
# so the script stays usable from any shell.
#
# Run from anywhere:
#   * inside the Media Sync app            -> syncs directly
#   * HA Core (shell_command/automation)   -> hops into an SSH app
#   * an SSH app terminal (manual)         -> syncs directly
set -eu

usage() {
  cat <<'USAGE'
usage: media-sync.sh [options]

  -n, --dry-run           show what would happen, change nothing
      --scan-only         only look for things to delete, copy nothing
      --pull-only         remote -> local only
      --push-only         local -> remote only
      --yes               assume "yes" to delete confirmations (DANGEROUS)
      --no-delete-check   do not look for things to delete (faster)
      --force-removal     remove a confirmed folder even when excluded files
                          are still inside it
  -q, --quiet             print totals only
  -v, --verbose           print every file transferred
      --changes           print every file and what changed about it
      --progress          print every file, plus how far along the run is
      --no-hop            internal: we already have rsync here
USAGE
}

# ============================================================================
#  CONFIGURATION
# ============================================================================
# The remote server to synchronize with. REMOTE_BASE is the path the remote
# side of each pair below is relative to; leave it empty for the login's home
# directory. A Hetzner Storage Box, for example, would be reached with
# REMOTE_HOST=<user>.your-storagebox.de, REMOTE_USER=<user>, REMOTE_PORT=23.
REMOTE_USER="${REMOTE_USER:-}"
REMOTE_HOST="${REMOTE_HOST:-}"
REMOTE_PORT="${REMOTE_PORT:-22}"
REMOTE_BASE="${REMOTE_BASE:-}"

MEDIA_DIR="${MEDIA_DIR:-/media}"

# --- what to synchronise ----------------------------------------------------
# One pair per line:
#
#   <label>|<remote subpath>|<local path>|<excludes for this pair>
#
#   remote subpath  relative to REMOTE_BASE; use "." for its root
#   excludes        comma-separated, applied to this pair only
#
SYNC_PAIRS="${SYNC_PAIRS:-
Media|Media|$MEDIA_DIR/Media|
Documents|.|$MEDIA_DIR/Documents|/Media/
}"

# --- folders to include -----------------------------------------------------
# If non-empty, ONLY these top-level folders are synced inside every pair;
# everything else at the pair root is ignored in both directions.
INCLUDE_DIRS="${INCLUDE_DIRS:-}"

# How much rsync prints: quiet, summary, files, changes, progress or debug.
VERBOSITY="${VERBOSITY:-summary}"

# --- never synchronise ------------------------------------------------------
# rsync filter syntax: a leading / anchors the pattern to the pair root,
# otherwise it matches at any depth. A trailing / matches directories only.
EXCLUDE_PATTERNS="${EXCLUDE_PATTERNS:-
.DS_Store
._*
Thumbs.db
desktop.ini
@eaDir/
#recycle/
#snapshot/
lost+found/
.Trash-*/
\$RECYCLE.BIN/
System Volume Information/
*.tmp
*.partial
*.!qB
.stfolder/
.stversions/
}"

# --- transport / bookkeeping ------------------------------------------------
HOP_USER="${HOP_USER:-matthias}"
HOP_HOST="${HOP_HOST:-localhost}"
HOP_PORT="${HOP_PORT:-12488}"

SSH_DIR="${SSH_DIR:-/config/.ssh}"
HOP_KEY="${HOP_KEY:-$SSH_DIR/hass-addon.key}"
REMOTE_KEY="${REMOTE_KEY:-$SSH_DIR/remote.key}"
KNOWN_HOSTS="${KNOWN_HOSTS:-$SSH_DIR/known_hosts}"

STATE_DIR="${STATE_DIR:-/config/media_sync}"
STATE_FILE="${STATE_FILE:-$STATE_DIR/state.json}"
DELETE_REPORT="${DELETE_REPORT:-$STATE_DIR/deletions.txt}"

LOCK_DIR="${LOCK_DIR:-/tmp/media-sync.lock}"
FILTER_FILE="/tmp/media-sync.filter.$$"
PENDING_FILE="/tmp/media-sync.pending.$$"
SELF="${SELF:-/config/scripts/media-sync.sh}"
# ============================================================================

# ---- arguments -------------------------------------------------------------
NO_HOP=0; DRY_RUN=0; SCAN_ONLY=0; DO_PULL=1; DO_PUSH=1; ASSUME_YES=0
FORCE_REMOVAL=0
CHECK_DELETES=1
FWD=""

for arg in "$@"; do
  case "$arg" in
    -n|--dry-run)      DRY_RUN=1;       FWD="$FWD --dry-run" ;;
    --scan-only)       SCAN_ONLY=1;     FWD="$FWD --scan-only" ;;
    --pull-only)       DO_PUSH=0;       FWD="$FWD --pull-only" ;;
    --push-only)       DO_PULL=0;       FWD="$FWD --push-only" ;;
    --yes)             ASSUME_YES=1;    FWD="$FWD --yes" ;;
    --no-delete-check) CHECK_DELETES=0; FWD="$FWD --no-delete-check" ;;
    --force-removal)   FORCE_REMOVAL=1; FWD="$FWD --force-removal" ;;
    -q|--quiet)        VERBOSITY=quiet;    FWD="$FWD --quiet" ;;
    -v|--verbose)      VERBOSITY=files;    FWD="$FWD --verbose" ;;
    --changes)         VERBOSITY=changes;  FWD="$FWD --changes" ;;
    --progress)        VERBOSITY=progress; FWD="$FWD --progress" ;;
    --no-hop)          NO_HOP=1 ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$SCAN_ONLY" -eq 1 ]; then MODE="scan"
elif [ "$DRY_RUN" -eq 1 ];  then MODE="dry_run"
else                             MODE="sync"; fi

if   [ "$DO_PULL" -eq 1 ] && [ "$DO_PUSH" -eq 1 ]; then DIRECTION="both"
elif [ "$DO_PULL" -eq 1 ];                         then DIRECTION="pull"
else                                                    DIRECTION="push"; fi

now_iso() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

STARTED="$(now_iso)"
FINISHED=0
LAST_SUCCESS=""

# ---- state file ------------------------------------------------------------
# Read a single string field back out of the previous state file, so a scan or
# a dry run does not lose the timestamp of the last real sync.
prev_field() {
  [ -f "$STATE_FILE" ] || return 0
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$STATE_FILE" | head -1
}

json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

write_state() {   # $1 = status, $2 = error text (may be empty)
  _pending=""
  _count=0
  if [ -s "$PENDING_FILE" ]; then
    _count="$(wc -l < "$PENDING_FILE" | tr -d ' ')"
    _pending="$(sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/' "$PENDING_FILE" \
                | tr '\n' ',' | sed 's/,$//')"
  fi
  [ "$1" = "running" ] && _finished="" || _finished="$(now_iso)"

  mkdir -p "$(dirname "$STATE_FILE")"
  cat > "$STATE_FILE" <<JSON
{
  "status": "$1",
  "mode": "$MODE",
  "direction": "$DIRECTION",
  "started": "$STARTED",
  "finished": "$_finished",
  "last_success": "$LAST_SUCCESS",
  "pending_count": $_count,
  "pending": [$_pending],
  "error": "$(json_escape "${2:-}")"
}
JSON
}

die() {
  log "ERROR: $*"
  FINISHED=1
  write_state failed "$*"
  exit 1
}

cleanup() {
  [ "$FINISHED" -eq 0 ] && write_state failed "interrupted"
  [ "${LOCK_HELD:-0}" -eq 1 ] && rmdir "$LOCK_DIR" 2>/dev/null
  rm -f "$FILTER_FILE" "$PENDING_FILE" 2>/dev/null
  true
}
LOCK_HELD=0

# /config is frequently 0644 via Samba/VSCode; ssh rejects that. Work on a
# private copy instead of chmod'ing the original, which may not be permitted.
private_copy() {
  _dst="/tmp/$(basename "$1").priv"
  cp "$1" "$_dst" && chmod 600 "$_dst" && echo "$_dst"
}

# Only ever true on a real terminal. Started by the app or an automation this
# returns 1, so deletions are reported and skipped rather than silently applied.
confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  [ -t 0 ] || return 1
  printf '%s [y/N] ' "$1"
  read -r _ans < /dev/tty || return 1
  case "$_ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# strip blank lines, comments and stray whitespace from a config list
clean_list() {
  printf '%s\n' "$1" \
    | sed 's/[[:space:]]*$//; s/^[[:space:]]*//' \
    | grep -v '^$' | grep -v '^#' || true
}

SSH_OPTS="-o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$KNOWN_HOSTS -o ConnectTimeout=20"

# ---- step 1: no rsync here? then delegate to an SSH app -------------------
if [ "$NO_HOP" -eq 0 ] && ! command -v rsync >/dev/null 2>&1; then
  log "no rsync here - delegating over SSH"
  [ -f "$HOP_KEY" ] || { log "ERROR: missing $HOP_KEY"; exit 1; }
  command -v ssh >/dev/null 2>&1 || { log "ERROR: no ssh client here"; exit 1; }
  key="$(private_copy "$HOP_KEY")"
  # keep a tty when there is one, so the delete prompt still works over the hop
  if [ -t 0 ] && [ -t 1 ]; then HOPTTY="-t"; else HOPTTY="-T -n"; fi
  exec ssh -p "$HOP_PORT" -i "$key" $SSH_OPTS $HOPTTY \
      "$HOP_USER@$HOP_HOST" "sh $SELF --no-hop$FWD"
fi

# ---- step 2: writing to the media library needs root ----------------------
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
  exec sudo -n sh "$SELF" --no-hop $FWD
fi

# ---- step 3: setup ---------------------------------------------------------
trap cleanup EXIT INT TERM
mkdir -p "$(dirname "$STATE_FILE")"
: > "$PENDING_FILE"
LAST_SUCCESS="$(prev_field last_success)"

# Neither a dry run nor a scan writes anything, so they take no lock.
if [ "$MODE" = "sync" ]; then
  mkdir "$LOCK_DIR" 2>/dev/null || {
    log "sync already running - skipping"
    FINISHED=1
    exit 0
  }
  LOCK_HELD=1
fi

write_state running ""

[ -n "$REMOTE_HOST" ] || die "no remote server configured (REMOTE_HOST is empty)"
[ -n "$REMOTE_USER" ] || die "no remote user configured (REMOTE_USER is empty)"
[ -f "$REMOTE_KEY" ] || die "missing $REMOTE_KEY"
remotekey="$(private_copy "$REMOTE_KEY")"
RSH="ssh -p $REMOTE_PORT -i $remotekey $SSH_OPTS"

# -a  : recursive, preserves times/perms -> transfers only what changed
# -u  : never overwrite a destination file that is newer than the source
# Run in both directions, this yields newest-wins per file.
RSYNC_BASE="-a -u --partial --human-readable --modify-window=1"

if [ "$DRY_RUN" -eq 1 ]; then
  RSYNC_OUT="--dry-run --itemize-changes --stats"
else
  case "$VERBOSITY" in
    quiet)    RSYNC_OUT="--info=stats0" ;;
    files)    RSYNC_OUT="-v --info=stats2" ;;
    changes)  RSYNC_OUT="-v --itemize-changes --info=stats2" ;;
    # A per-file progress bar only makes sense on a terminal. Anywhere else
    # use the single aggregate line, so a log stays readable.
    progress) if [ -t 1 ]; then RSYNC_OUT="-v --progress --info=stats2"
              else                RSYNC_OUT="-v --info=progress2,stats2"; fi ;;
    debug)    RSYNC_OUT="-vv --itemize-changes --info=progress2,stats2" ;;
    *)        RSYNC_OUT="--info=stats2" ;;
  esac
fi

# ---- filter compilation ----------------------------------------------------
# One merge file per pair. Order matters: rsync applies the FIRST matching
# rule, so excludes are emitted before the include whitelist.
build_filter() {   # $1 = comma-separated excludes for this pair
  : > "$FILTER_FILE"

  clean_list "$(printf '%s' "$1" | tr ',' '\n')" | sed 's/^/- /' >> "$FILTER_FILE"
  clean_list "$EXCLUDE_PATTERNS" | sed 's/^/- /' >> "$FILTER_FILE"

  _inc="$(clean_list "$INCLUDE_DIRS")"
  if [ -n "$_inc" ]; then
    printf '%s\n' "$_inc" | sed 's#^/##; s#/*$##' | while IFS= read -r d; do
      printf '+ /%s/\n+ /%s/**\n' "$d" "$d"
    done >> "$FILTER_FILE"
    echo '- /*' >> "$FILTER_FILE"          # block everything not whitelisted
  fi
}

# ---- deletion handling -----------------------------------------------------
# Lists what --delete *would* remove from the destination, without doing it.
scan_deletes() {
  rsync $RSYNC_BASE --dry-run --delete --itemize-changes "$FILTER_OPT" \
      -e "$RSH" "$1" "$2" < /dev/null 2>/dev/null \
    | sed -n 's/^\*deleting  *//p'
}

record_pending() {   # $1 = label, $2 = newline separated paths
  printf '%s\n' "$2" | sed "s|^|$1: |" >> "$PENDING_FILE"
}

# Wrap a string so a remote shell sees it as one literal argument. Done with
# parameter expansion rather than sed, because the backslash needed to escape
# an embedded quote does not survive the layers of sed quoting.
shell_quote() {
  _in="$1"; _out=""
  while :; do
    case "$_in" in
      *"'"*) _out="${_out}${_in%%\'*}'\''"; _in="${_in#*\'}" ;;
      *)     break ;;
    esac
  done
  printf "'%s'" "${_out}${_in}"
}

# rsync will not delete a directory that still holds excluded files, and says
# so. Finish the job for exactly the paths it named - never anything else.
remove_leftover() {   # $1 = destination root, $2 = path relative to it
  _root="$1"; _rel="$2"

  case "$_rel" in
    ''|/*|*..*)
      log "[$label] refusing to remove an unexpected path: $_rel"
      return 0
      ;;
  esac

  case "$_root" in
    *:*)
      _host="${_root%%:*}"
      _path="${_root#*:}"
      log "[$label] removing leftover on the server: $_rel"
      $RSH "$_host" "rm -rf -- $(shell_quote "${_path}${_rel}")" </dev/null \
        || log "[$label] could not remove $_rel on the server"
      ;;
    *)
      log "[$label] removing leftover: $_rel"
      rm -rf -- "${_root}${_rel}" \
        || log "[$label] could not remove $_rel"
      ;;
  esac
}

sync_one_way() {
  label="$1"; src="$2"; dst="$3"
  del_opt=""

  if [ "$CHECK_DELETES" -eq 1 ]; then
    dels="$(scan_deletes "$src" "$dst")"
    if [ -n "$dels" ]; then
      count="$(printf '%s\n' "$dels" | wc -l | tr -d ' ')"
      log "[$label] $count item(s) present in the destination but not the source:"
      printf '%s\n' "$dels" | sed 's/^/      /'
      {
        echo "### $label  $(now_iso)  -  $count item(s)"
        echo "###   from: $src"
        echo "###   to:   $dst"
        printf '%s\n' "$dels"
        echo
      } >> "$DELETE_REPORT"

      if [ "$MODE" != "sync" ]; then
        record_pending "$label" "$dels"
        log "[$label] $MODE - $count item(s) would be deleted, left alone"
      elif confirm "[$label] Delete these $count item(s) from the destination?"; then
        del_opt="--delete"
        log "[$label] deletions confirmed"
      else
        record_pending "$label" "$dels"
        log "[$label] not confirmed - $count item(s) left alone"
      fi
    fi
  fi

  [ "$SCAN_ONLY" -eq 1 ] && return 0

  log "[$label] syncing..."

  # Keep the output streaming while also capturing it, so leftovers can be
  # picked out afterwards. $? of a pipeline is tee's, so stash rsync's own.
  _rsync_out="/tmp/media-sync.out.$$"
  _rsync_rc="/tmp/media-sync.rc.$$"
  {
    rsync $RSYNC_BASE $RSYNC_OUT $del_opt "$FILTER_OPT" -e "$RSH" "$src" "$dst" \
      < /dev/null 2>&1
    echo $? > "$_rsync_rc"
  } | tee "$_rsync_out"
  _status="$(cat "$_rsync_rc" 2>/dev/null || echo 1)"
  rm -f "$_rsync_rc"

  # rsync leaves a folder behind when excluded files are still inside it.
  # Only clear those up when asked to, and only for the paths rsync named.
  if [ -n "$del_opt" ] && [ -s "$_rsync_out" ]; then
    _stuck="$(sed -n 's/^cannot delete non-empty directory: //p' "$_rsync_out")"
    if [ -n "$_stuck" ]; then
      if [ "$FORCE_REMOVAL" -eq 1 ]; then
        printf '%s\n' "$_stuck" | while IFS= read -r leftover; do
          remove_leftover "$dst" "$leftover"
        done
      else
        _n="$(printf '%s\n' "$_stuck" | wc -l | tr -d ' ')"
        log "[$label] $_n folder(s) stayed behind because excluded files are still inside:"
        printf '%s\n' "$_stuck" | sed 's/^/      /'
        log "[$label] turn on \"Remove leftover folders\" in the settings to clear these"
      fi
    fi
  fi
  rm -f "$_rsync_out"

  [ "$_status" -eq 0 ] || die "[$label] rsync failed (exit $_status)"
}

# ---- step 4: run both directions for every pair ----------------------------
[ "$DRY_RUN" -eq 1 ] && log "DRY RUN - no files will be written"
[ "$SCAN_ONLY" -eq 1 ] && log "SCAN ONLY - looking for deletion candidates"
log "direction: $DIRECTION"
[ -n "$(clean_list "$INCLUDE_DIRS")" ] \
  && log "include filter active: $(clean_list "$INCLUDE_DIRS" | tr '\n' ' ')"

FILTER_OPT="--exclude-from=$FILTER_FILE"

while IFS='|' read -r name rsub lloc pair_excl; do
  [ -n "$name" ] || continue

  case "$rsub" in
    .|"") rpath="${REMOTE_BASE:+$REMOTE_BASE/}" ;;
    *)    rpath="${REMOTE_BASE:+$REMOTE_BASE/}${rsub%/}/" ;;
  esac
  lpath="${lloc%/}/"
  remote="$REMOTE_USER@$REMOTE_HOST:$rpath"

  build_filter "$pair_excl"
  [ "$MODE" = "sync" ] && mkdir -p "$lpath"

  # Deletions are resolved per direction *before* the merge: once both sides
  # have been merged, nothing looks deleted any more.
  if [ "$DO_PULL" -eq 1 ]; then sync_one_way "$name pull" "$remote" "$lpath"; fi
  if [ "$DO_PUSH" -eq 1 ]; then sync_one_way "$name push" "$lpath"  "$remote"; fi
done <<EOF
$SYNC_PAIRS
EOF

[ "$MODE" = "sync" ] && LAST_SUCCESS="$(now_iso)"
FINISHED=1
write_state ok ""

# Close every run with what was found, so the outcome is readable without
# scrolling back through the whole run or opening the report file.
summarise_pending() {
  [ -s "$PENDING_FILE" ] || return 0
  _total="$(wc -l < "$PENDING_FILE" | tr -d ' ')"
  log "$_total item(s) exist on one side only and were left alone:"
  sed 's/:.*//' "$PENDING_FILE" | sort | uniq -c \
    | while read -r _n _label; do
        printf '      %s in [%s]\n' "$_n" "$_label"
      done
  log "Full list: $DELETE_REPORT"
  [ "$MODE" = "sync" ] && log "Confirm or dismiss them from the repair notification in Home Assistant."
  true
}

case "$MODE" in
  dry_run) log "Dry run complete - nothing was changed" ;;
  scan)    log "Scan complete" ;;
  *)       log "Done" ;;
esac

summarise_pending
