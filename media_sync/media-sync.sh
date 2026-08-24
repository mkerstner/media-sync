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
      --resolve           apply the keep/delete decisions recorded by Home
                          Assistant, then exit
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

# How to reach the remote side: "ssh" drives rsync over SSH, "webdav" drives
# rclone against a WebDAV share such as Nextcloud.
PROTOCOL="${PROTOCOL:-ssh}"
WEBDAV_URL="${WEBDAV_URL:-}"
WEBDAV_USER="${WEBDAV_USER:-}"
WEBDAV_PASS="${WEBDAV_PASS:-}"

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
# Full candidate list, rewritten each run. The review UI groups these by
# folder, but every action resolves back to exact paths from here - a folder
# with two candidates may hold hundreds of properly synced files.
PENDING_TSV="${PENDING_TSV:-$STATE_DIR/pending.tsv}"
# Decisions written by the integration: action 	 label 	 folder
DECISIONS_FILE="${DECISIONS_FILE:-$STATE_DIR/decisions.tsv}"
# Most folder groups to show before rolling up to a shallower level.
MAX_GROUPS="${MAX_GROUPS:-40}"

LOCK_DIR="${LOCK_DIR:-/tmp/media-sync.lock}"
FILTER_FILE="/tmp/media-sync.filter.$$"
PENDING_FILE="/tmp/media-sync.pending.$$"
SELF="${SELF:-/config/scripts/media-sync.sh}"
# ============================================================================

# ---- arguments -------------------------------------------------------------
NO_HOP=0; DRY_RUN=0; SCAN_ONLY=0; DO_PULL=1; DO_PUSH=1; ASSUME_YES=0
RESOLVE=0
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
    --resolve)         RESOLVE=1;       FWD="$FWD --resolve" ;;
    -q|--quiet)        VERBOSITY=quiet;    FWD="$FWD --quiet" ;;
    -v|--verbose)      VERBOSITY=files;    FWD="$FWD --verbose" ;;
    --changes)         VERBOSITY=changes;  FWD="$FWD --changes" ;;
    --progress)        VERBOSITY=progress; FWD="$FWD --progress" ;;
    --no-hop)          NO_HOP=1 ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [ "$RESOLVE" -eq 1 ];   then MODE="resolve"
elif [ "$SCAN_ONLY" -eq 1 ]; then MODE="scan"
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

# Turn the recorded candidates into the two JSON arrays the state file needs.
# Prints exactly two lines: the legacy flat list first, the grouped list
# second.
#
# Grouping exists because a flat list of a few thousand orphans is not
# reviewable, while they almost always sit in a handful of folders. Group by
# directory at the deepest level that still fits MAX_GROUPS, so a run stays
# specific when it can and coarse only when it must.
#
# The groups are only how the list is *shown*. Every action resolves back to
# exact paths from PENDING_TSV, because a folder holding two candidates may
# hold hundreds of correctly synced files as well.
#
# No backslash appears in the awk below on purpose: it travels through several
# quoting layers, so the field separator and the JSON escapes are built by
# code point instead.
pending_json() {
  [ -s "$PENDING_FILE" ] || { printf '\n\n'; return 0; }
  awk -v MAX="$MAX_GROUPS" -v LEGACY_MAX=200 -v EX=2 '
    BEGIN {
      FS = sprintf("%c", 9); BS = sprintf("%c", 92); QT = sprintf("%c", 34)
      SEP = sprintf("%c", 31)
    }

    function esc(s,   out, i, c) {
      out = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == BS || c == QT) out = out BS c
        else out = out c
      }
      return out
    }

    function q(s) { return QT esc(s) QT }

    function key(p, d,   parts, m, i, out) {
      m = split(p, parts, "/")
      if (m <= 1) return "(root)"
      if (d > m - 1) d = m - 1
      out = parts[1]
      for (i = 2; i <= d; i++) out = out "/" parts[i]
      return out
    }

    { label[NR] = $1; side[NR] = $2; path[NR] = $3; n = NR }

    END {
      if (n == 0) { print ""; print ""; exit 0 }
      if (MAX == 0) MAX = 40

      # Older integrations read a flat "label: path" list. Keep feeding them
      # one, capped, so a mismatched pair still shows something rather than
      # silently reporting nothing pending.
      flat = ""
      for (i = 1; i <= n && i <= LEGACY_MAX; i++) {
        if (i > 1) flat = flat ","
        flat = flat q(label[i] ": " path[i])
      }
      print flat

      for (d = 6; d >= 1; d--) {
        delete seen
        groups = 0
        for (i = 1; i <= n; i++) {
          k = label[i] SUBSEP side[i] SUBSEP key(path[i], d)
          if (!(k in seen)) { seen[k] = 1; groups++ }
        }
        if (groups <= MAX) break
      }

      for (i = 1; i <= n; i++) {
        g = key(path[i], d)
        k = label[i] SUBSEP side[i] SUBSEP g
        count[k]++
        if (!(k in order)) { order[k] = ++seq; klist[seq] = k }
        # A folder name alone says nothing when it stands for one file, so
        # carry a couple of real names. Relative to the folder already shown,
        # so the row does not repeat itself.
        if (count[k] <= EX) {
          rel = (g == "(root)") ? path[i] : substr(path[i], length(g) + 2)
          ex[k] = (count[k] == 1) ? rel : ex[k] SEP rel
        }
      }

      out = ""
      for (i = 1; i <= seq; i++) {
        split(klist[i], f, SUBSEP)
        one = "{" q("label") ":" q(f[1])
        one = one "," q("side") ":" q(f[2])
        one = one "," q("folder") ":" q(f[3])
        one = one "," q("count") ":" count[klist[i]]
        one = one "," q("examples") ":["
        m = split(ex[klist[i]], e, SEP)
        for (j = 1; j <= m; j++) {
          if (j > 1) one = one ","
          one = one q(e[j])
        }
        one = one "]}"
        if (i > 1) out = out ","
        out = out one
      }
      print out
    }
  ' "$PENDING_FILE"
}

write_state() {   # $1 = status, $2 = error text (may be empty)
  _pending=""
  _groups=""
  _count=0
  if [ -s "$PENDING_FILE" ]; then
    _count="$(wc -l < "$PENDING_FILE" | tr -d ' ')"
    _both="$(pending_json)"
    _pending="$(printf '%s\n' "$_both" | sed -n 1p)"
    _groups="$(printf '%s\n' "$_both" | sed -n 2p)"
    # Keep the full list where a later --resolve can find it. The state file
    # only carries the grouped summary, so it stays small enough to re-read
    # every few seconds.
    mkdir -p "$(dirname "$PENDING_TSV")"
    cp "$PENDING_FILE" "$PENDING_TSV"
  else
    rm -f "$PENDING_TSV" 2>/dev/null || true
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
  "pending_groups": [$_groups],
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

# ---- transport selection ---------------------------------------------------
# Everything below this point works in terms of REMOTE_PREFIX and the
# transport_* functions, so the sync, review and resolve logic is the same
# whichever protocol is in use.
case "$PROTOCOL" in
  ssh)
    [ -n "$REMOTE_HOST" ] || die "no remote server configured (REMOTE_HOST is empty)"
    [ -n "$REMOTE_USER" ] || die "no remote user configured (REMOTE_USER is empty)"
    [ -f "$REMOTE_KEY" ] || die "missing $REMOTE_KEY"
    remotekey="$(private_copy "$REMOTE_KEY")"
    RSH="ssh -p $REMOTE_PORT -i $remotekey $SSH_OPTS"
    REMOTE_PREFIX="$REMOTE_USER@$REMOTE_HOST:"
    ;;
  webdav)
    command -v rclone >/dev/null 2>&1 || die "rclone is not installed in this image"
    [ -n "$WEBDAV_URL" ]  || die "no WebDAV address configured (WEBDAV_URL is empty)"
    [ -n "$WEBDAV_USER" ] || die "no WebDAV user configured (WEBDAV_USER is empty)"
    [ -n "$WEBDAV_PASS" ] || die "no WebDAV password configured (WEBDAV_PASS is empty)"
    # Configure the backend through the environment: rclone writes no config
    # file this way, so the credential never lands in a file of ours. Obscuring
    # is what rclone expects of a stored password, and reading it from stdin
    # keeps the plaintext off the command line. rclone obscures the hyphen
    # itself when stdin is empty, which the check above rules out.
    RCLONE_CONFIG_DAV_TYPE=webdav
    RCLONE_CONFIG_DAV_VENDOR=nextcloud
    RCLONE_CONFIG_DAV_URL="$WEBDAV_URL"
    RCLONE_CONFIG_DAV_USER="$WEBDAV_USER"
    RCLONE_CONFIG_DAV_PASS="$(printf '%s\n' "$WEBDAV_PASS" | rclone obscure -)"
    export RCLONE_CONFIG_DAV_TYPE RCLONE_CONFIG_DAV_VENDOR RCLONE_CONFIG_DAV_URL
    export RCLONE_CONFIG_DAV_USER RCLONE_CONFIG_DAV_PASS
    RSH=""
    REMOTE_PREFIX="dav:"
    ;;
  *)
    die "unknown protocol: $PROTOCOL (expected ssh or webdav)"
    ;;
esac

# -a  : recursive, preserves times/perms -> transfers only what changed
# -u  : never overwrite a destination file that is newer than the source
# Run in both directions, this yields newest-wins per file.
RSYNC_BASE="-a -u --partial --human-readable --modify-window=1"

# --update is rclone's equivalent of rsync -u: never replace a destination
# file that is newer. Run both ways, that is the same newest-wins merge.
RCLONE_BASE="--update --checkers 8 --transfers 4"

if [ "$DRY_RUN" -eq 1 ]; then
  RSYNC_OUT="--dry-run --itemize-changes --stats"
  RCLONE_OUT="--dry-run -v"
else
  case "$VERBOSITY" in
    quiet)    RSYNC_OUT="--info=stats0";                    RCLONE_OUT="-q" ;;
    files)    RSYNC_OUT="-v --info=stats2";                 RCLONE_OUT="-v" ;;
    changes)  RSYNC_OUT="-v --itemize-changes --info=stats2"; RCLONE_OUT="-v" ;;
    # A per-file progress bar only makes sense on a terminal. Anywhere else
    # use the single aggregate line, so a log stays readable.
    progress) if [ -t 1 ]; then RSYNC_OUT="-v --progress --info=stats2"
                                RCLONE_OUT="-v --progress"
              else                RSYNC_OUT="-v --info=progress2,stats2"
                                RCLONE_OUT="-v --stats 15s"; fi ;;
    debug)    RSYNC_OUT="-vv --itemize-changes --info=progress2,stats2"
              RCLONE_OUT="-vv" ;;
    *)        RSYNC_OUT="--info=stats2";                    RCLONE_OUT="" ;;
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
# ---- transport operations --------------------------------------------------
# Four things the sync needs from a protocol. Everything above and below is
# shared: grouping, the review, decisions and the state file do not care how
# bytes move.

# Paths present in the destination but not in the source. These are the
# deletion candidates the review asks about.
# Move the files themselves. A non-empty $3 means deletions were confirmed,
# which is rclone's "sync" rather than "copy".
transport_sync() {   # $1 = source, $2 = destination, $3 = delete option
  if [ "$PROTOCOL" = "webdav" ]; then
    if [ -n "$3" ]; then _verb=sync; else _verb=copy; fi
    # The filter file is written in rsync syntax. rclone reads the same
    # leading "+" and "-" and the same ** wildcard, which covers what
    # build_filter emits; anything more exotic would need translating.
    rclone $_verb $RCLONE_BASE $RCLONE_OUT --filter-from "$FILTER_FILE" \
        "$1" "$2" < /dev/null 2>&1
  else
    rsync $RSYNC_BASE $RSYNC_OUT $3 "$FILTER_OPT" -e "$RSH" "$1" "$2" \
        < /dev/null 2>&1
  fi
}

scan_deletes() {   # $1 = source, $2 = destination
  if [ "$PROTOCOL" = "webdav" ]; then
    # --missing-on-src is exactly this question, so there is no output format
    # to parse. --size-only keeps it from hashing a whole library to answer a
    # question about which names exist.
    #
    # The trailing "|| true" is load-bearing: rclone check reports a non-zero
    # status whenever the two sides differ, which is the normal case here. The
    # status says nothing about whether the check worked, and this runs inside
    # a command substitution, so letting it through ends the run under set -e
    # before anything has been logged. A connection that genuinely fails still
    # surfaces at the transfer step.
    rclone check "$1" "$2" --size-only --missing-on-src - \
        --filter-from "$FILTER_FILE" < /dev/null 2>/dev/null || true
  else
    rsync $RSYNC_BASE --dry-run --delete --itemize-changes "$FILTER_OPT" \
        -e "$RSH" "$1" "$2" < /dev/null 2>/dev/null \
      | sed -n 's/^\*deleting  *//p'
  fi
}

# Copy exactly the paths listed in a file, and nothing else.
transport_copy_files() {   # $1 = source, $2 = destination, $3 = list file
  if [ "$PROTOCOL" = "webdav" ]; then
    rclone copy $RCLONE_BASE --files-from "$3" "$1" "$2" \
        < /dev/null 2>&1
  else
    rsync $RSYNC_BASE --files-from="$3" -e "$RSH" "$1" "$2" \
        < /dev/null 2>&1
  fi
}

# Remove one recorded path from whichever side still holds it.
# Remove one recorded path from whichever side still holds it. Dispatch is on
# the shape of the root, not the protocol, so a local destination is handled
# the same way under either.
transport_remove_path() {   # $1 = root, $2 = path relative to it
  case "$1" in
    dav:*)
      # deletefile removes a single file, purge a directory and its contents.
      # Which one this path is is not known here, so try the file first.
      rclone deletefile "$1$2" < /dev/null 2>/dev/null \
        || rclone purge "$1$2" < /dev/null 2>/dev/null
      ;;
    *:*)
      _host="${1%%:*}"
      _path="${1#*:}"
      $RSH "$_host" "rm -rf -- $(shell_quote "${_path}$2")" < /dev/null
      ;;
    *)
      rm -rf -- "$1$2"
      ;;
  esac
}

# Record deletion candidates for review. Written as TSV so the review UI can
# say which side holds each file: the candidates of a "pull" live on the local
# side, a "push" leaves them on the server.
record_pending() {   # $1 = label, $2 = newline separated paths
  case "$1" in
    *" pull") _side=local ;;
    *" push") _side=remote ;;
    *)        _side=unknown ;;
  esac
  printf '%s\n' "$2" | while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    printf '%s\t%s\t%s\n' "$1" "$_side" "$_p"
  done >> "$PENDING_FILE"
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
    *:*) log "[$label] removing leftover on the server: $_rel" ;;
    *)   log "[$label] removing leftover: $_rel" ;;
  esac
  transport_remove_path "$_root" "$_rel" \
    || log "[$label] could not remove $_rel"
}

# ---- readable output -------------------------------------------------------
# rsync's --itemize-changes codes are meant for scripts, not people. Turn them
# into words. The eleven columns are YXcstpoguax: Y is how the item was
# updated, X is what kind of item it is, and the rest say which attributes
# differ ('.' same, letter differs, '+' newly created).
#
# Written without regex intervals, because busybox awk is what runs this.
humanize() {
  awk '
    {
      if (substr($0,1,10) == "*deleting ") {
        printf "       %-10s %s\n", "deleted", substr($0,13)
        next
      }

      ok = 0
      if (length($0) > 12 && substr($0,12,1) == " ") {
        y = substr($0,1,1); x = substr($0,2,1); a = substr($0,3,9)
        if (index("<>ch.", y) > 0 && index("fdLDS", x) > 0) {
          ok = 1
          for (i = 1; i <= 9; i++)
            if (index(".+cstpoguax", substr(a,i,1)) == 0) { ok = 0; break }
        }
      }
      if (!ok) { print; next }

      arrow = (y == "<") ? "up  " : (y == ">") ? "down" : "    "
      if (a == "+++++++++")                  verb = (x == "d") ? "new folder" : "new"
      else if (y == ".")                     verb = "metadata"
      else if (index(a,"s") || index(a,"c")) verb = "updated"
      else                                   verb = "timestamp"

      printf "  %s %-10s %s\n", arrow, verb, substr($0,13)
    }
  '
}

# Count what a run actually did, from the same captured output. Silent unless
# rsync was asked to itemize, since otherwise there is nothing to count.
tally() {   # $1 = label, $2 = captured raw rsync output
  [ -s "$2" ] || return 0
  awk -v label="$1" '
    {
      if (substr($0,1,10) == "*deleting ") { del++; next }

      ok = 0
      if (length($0) > 12 && substr($0,12,1) == " ") {
        y = substr($0,1,1); x = substr($0,2,1); a = substr($0,3,9)
        if (index("<>ch.", y) > 0 && index("fdLDS", x) > 0) {
          ok = 1
          for (i = 1; i <= 9; i++)
            if (index(".+cstpoguax", substr(a,i,1)) == 0) { ok = 0; break }
        }
      }
      if (!ok) next

      if (a == "+++++++++")                  { if (x == "d") dir++; else new++ }
      else if (y == ".")                     meta++
      else if (index(a,"s") || index(a,"c")) upd++
      else                                   ts++
    }
    END {
      if (new + upd + ts + meta + dir + del == 0) exit 0

      out = (new+0) " new, " (upd+0) " updated"
      if (ts   > 0) out = out ", " ts " timestamp-only"
      if (meta > 0) out = out ", " meta " metadata"
      if (dir  > 0) out = out ", " dir " new folder(s)"
      if (del  > 0) out = out ", " del " deleted"
      printf "[%s] %s\n", label, out

      # When nothing really changed but files moved anyway, the destination is
      # almost certainly not preserving times or permissions. Say so once,
      # rather than leaving it buried in the per-file lines.
      if (ts > 20 && ts > new + upd)
        printf "[%s] %d file(s) were re-sent only because their timestamps or permissions differ, not their contents.\n[%s] That usually means the destination cannot preserve them - see the app documentation.\n", label, ts, label
    }
  ' "$2"
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
    transport_sync "$src" "$dst" "$del_opt"
    echo $? > "$_rsync_rc"
  } | tee "$_rsync_out" | humanize
  _status="$(cat "$_rsync_rc" 2>/dev/null || echo 1)"
  rm -f "$_rsync_rc"

  # Raw output stays in $_rsync_out, so the leftover check below still reads
  # rsync's own wording. Only what reaches the log is rewritten.
  tally "$label" "$_rsync_out"

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

# ---- applying review decisions ---------------------------------------------
# Home Assistant records one line per reviewed folder: action, label, folder.
# "keep" copies the candidates back to the side that is missing them, "delete"
# removes them from the side that still has them.
#
# Decisions name folders because that is what a person can review. Actions
# always resolve back to the exact paths recorded in PENDING_TSV - a folder
# holding two candidates may hold hundreds of correctly synced files as well,
# and those must not be touched.

# Locate a pair by name. Prints "<remote spec><tab><local path>".
pair_paths() {   # $1 = pair name
  while IFS='|' read -r _n _rsub _lloc _x; do
    [ "$_n" = "$1" ] || continue
    case "$_rsub" in
      .|"") _rp="${REMOTE_BASE:+$REMOTE_BASE/}" ;;
      *)    _rp="${REMOTE_BASE:+$REMOTE_BASE/}${_rsub%/}/" ;;
    esac
    printf '%s@%s:%s\t%s\n' "$REMOTE_USER" "$REMOTE_HOST" "$_rp" "${_lloc%/}/"
    return 0
  done <<PAIRS
$SYNC_PAIRS
PAIRS
}

# Candidate paths for one label whose folder was marked with one action.
# A path belongs to a folder when the folder is its prefix, which holds
# whatever depth the grouping happened to pick.
select_paths() {   # $1 = label, $2 = keep|delete
  awk -v label="$1" -v action="$2" -v dec="$DECISIONS_FILE" '
    BEGIN {
      FS = sprintf("%c", 9)
      while ((getline line < dec) > 0) {
        split(line, f, FS)
        if (f[1] == action && f[2] == label) grp[f[3]] = 1
      }
      close(dec)
    }
    function in_group(p, g) {
      if (g == "(root)") return (index(p, "/") == 0)
      return (substr(p, 1, length(g) + 1) == g "/")
    }
    $1 == label {
      for (g in grp) if (in_group($3, g)) { print $3; next }
    }
  ' "$PENDING_TSV"
}

resolve_decisions() {
  if [ ! -s "$DECISIONS_FILE" ]; then
    log "no decisions to apply"
    return 0
  fi
  if [ ! -s "$PENDING_TSV" ]; then
    log "no recorded candidates left to act on"
    rm -f "$DECISIONS_FILE"
    return 0
  fi

  _acted="/tmp/media-sync.acted.$$"
  : > "$_acted"

  awk 'BEGIN { FS = sprintf("%c", 9) } { print $2 }' "$DECISIONS_FILE" \
    | sort -u | while IFS= read -r label; do
    [ -n "$label" ] || continue

    _name="${label% *}"
    _dir="${label##* }"
    _pp="$(pair_paths "$_name")"
    if [ -z "$_pp" ]; then
      log "[$label] that folder pair no longer exists - skipped"
      continue
    fi
    _remote="$(printf '%s' "$_pp" | cut -f1)"
    _local="$(printf '%s' "$_pp" | cut -f2)"
    case "$_dir" in
      pull) _holder="$_local";  _other="$_remote" ;;
      push) _holder="$_remote"; _other="$_local" ;;
      *)    log "[$label] unrecognised direction - skipped"; continue ;;
    esac

    build_filter ""

    # --- keep: copy the candidates to the side that is missing them ---------
    _keep="/tmp/media-sync.keep.$$"
    select_paths "$label" keep > "$_keep"
    if [ -s "$_keep" ]; then
      _n="$(wc -l < "$_keep" | tr -d ' ')"
      log "[$label] keeping $_n item(s) - copying to the other side"
      if [ "$DRY_RUN" -eq 1 ]; then
        log "[$label] dry run - nothing copied"
      elif transport_copy_files "$_holder" "$_other" "$_keep" | humanize; then
        awk -v l="$label" 'BEGIN{T=sprintf("%c",9)} {print l T $0}' "$_keep" >> "$_acted"
      else
        log "[$label] could not copy the kept items"
      fi
    fi
    rm -f "$_keep"

    # --- delete: only what is still genuinely missing on the other side -----
    _del="/tmp/media-sync.del.$$"
    select_paths "$label" delete > "$_del"
    if [ -s "$_del" ]; then
      _n="$(wc -l < "$_del" | tr -d ' ')"
      log "[$label] $_n item(s) marked for deletion - re-checking before removing"
      _still="/tmp/media-sync.still.$$"
      scan_deletes "$_other" "$_holder" > "$_still" 2>/dev/null || : > "$_still"
      _go="/tmp/media-sync.go.$$"
      awk 'NR==FNR { want[$0]=1; next } ($0 in want)' "$_del" "$_still" > "$_go"
      _skipped=$(( _n - $(wc -l < "$_go" | tr -d ' ') ))
      [ "$_skipped" -gt 0 ] && log "[$label] $_skipped no longer missing on the other side - left alone"
      if [ "$DRY_RUN" -eq 1 ]; then
        log "[$label] dry run - nothing deleted"
      else
        while IFS= read -r _p; do
          [ -n "$_p" ] || continue
          remove_leftover "$_holder" "$_p"
          printf '%s\t%s\n' "$label" "$_p" >> "$_acted"
        done < "$_go"
      fi
      rm -f "$_still" "$_go"
    fi
    rm -f "$_del"
  done

  # Whatever was not acted on is still pending, so the review list shrinks
  # instead of emptying.
  if [ -s "$_acted" ]; then
    awk 'BEGIN { FS = sprintf("%c", 9); OFS = FS }
         NR == FNR { done[$1 FS $2] = 1; next }
         !(($1 FS $3) in done)' "$_acted" "$PENDING_TSV" > "$PENDING_FILE"
  else
    cp "$PENDING_TSV" "$PENDING_FILE"
  fi
  rm -f "$_acted"
  [ "$DRY_RUN" -eq 1 ] || rm -f "$DECISIONS_FILE"
}

# ---- step 4: run both directions for every pair ----------------------------
[ "$DRY_RUN" -eq 1 ] && log "DRY RUN - no files will be written"
[ "$SCAN_ONLY" -eq 1 ] && log "SCAN ONLY - looking for deletion candidates"
log "direction: $DIRECTION"
[ -n "$(clean_list "$INCLUDE_DIRS")" ] \
  && log "include filter active: $(clean_list "$INCLUDE_DIRS" | tr '\n' ' ')"

FILTER_OPT="--exclude-from=$FILTER_FILE"

# A resolve run only applies decisions - it never syncs.
if [ "$RESOLVE" -eq 1 ]; then
  resolve_decisions
  FINISHED=1
  write_state ok ""
  log "Review decisions applied"
  exit 0
fi

while IFS='|' read -r name rsub lloc pair_excl; do
  [ -n "$name" ] || continue

  case "$rsub" in
    .|"") rpath="${REMOTE_BASE:+$REMOTE_BASE/}" ;;
    *)    rpath="${REMOTE_BASE:+$REMOTE_BASE/}${rsub%/}/" ;;
  esac
  lpath="${lloc%/}/"
  remote="${REMOTE_PREFIX}${rpath}"

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
  awk 'BEGIN { FS = sprintf("%c", 9) } { print $1 }' "$PENDING_FILE" | sort | uniq -c \
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
