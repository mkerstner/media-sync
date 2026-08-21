# Changelog

## 1.1.0

**Your settings are reset by this update.** Note down your server
details and folder pairs before updating, then enter them again
afterwards.

- The options screen is now grouped into Source server, Syncing,
  Folders and Advanced, instead of one long list.
- Because the settings moved into groups, every one of them has a new
  name internally, and the Supervisor cannot carry the old values
  across. In YAML a setting is now written as `source.remote_host`
  rather than `remote_host`.
- Labels lost their prefixes now that the group says what they are:
  "Remote server" became "Address", "SSH port" became "Port".

## 1.0.14

- The sync script now says in its header that it belongs to this app,
  where to find the documentation, and that the copy in
  `/config/scripts/` is replaced on every start.

## 1.0.13

- The shared log is now kept by age rather than by line count. A new
  `log_keep_days` setting decides how far back it goes, 14 days by
  default, and the file is capped at 1 MB as a backstop.

## 1.0.12

- Pointed the automation notes at the worked examples in the integration
  documentation.

## 1.0.10

- Every run now ends with a summary of what was left alone and where,
  instead of only pointing at the report file.

## 1.0.9

- Added a `dry_run` setting. While it is on, every run reports what it
  would do without copying or deleting anything, including runs started
  from Home Assistant.

## 1.0.8

- The settings now show readable names and an explanation of what each
  one does, instead of the raw option keys.

## 1.0.7

- Renamed the `rsync_verbosity` setting to `sync_log_verbosity`.
- Added a `changes` level, which shows what changed about each file.
  With six levels the setting now renders as a dropdown rather than a
  row of radio buttons.

## 1.0.6

- Added a `sync_log_verbosity` setting, so you can choose between totals only,
  one line per file, or live progress while a sync runs.

## 1.0.5

No functional changes. Released so the version in `config.yaml` lines up with
the GitHub release tag.

## 1.0.4

- The sync script is now placed at `/config/scripts/media-sync.sh` on every
  app start, so it is there to run by hand without copying it first.

## 1.0.3

- Added a shared activity log at `/config/media_sync/media-sync.log`, written
  by both the app and the integration, so you can see what was run and who
  asked for it. Recent activity is replayed into the Log tab on each run.
- Added a `log_level` setting.
- Dropped the 32-bit architectures. Home Assistant has deprecated 32-bit
  systems and their base images no longer build.
- Build from the Dockerfile again instead of pulling a prebuilt image, so the
  app installs before any image has been published.

Versions 1.0.1 and 1.0.2 were tagged on GitHub but never reached anyone as app
versions, because the version in `config.yaml` had not been bumped along with
them.

## 1.0.0

First release.

- Two-way sync between a remote server and the local media library, keeping
  whichever copy of a file is newer.
- Nothing is deleted without confirmation. Items present on only one side are
  listed and left alone.
- Folder pairs, include list and exclude patterns configurable in the settings.
- SSH key generated on first start; the public half is printed to the log.
