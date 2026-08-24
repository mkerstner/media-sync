# Changelog

## 1.8.0

- New Advanced setting **Parallel WebDAV requests**, default 16. A share has
  to be listed one folder at a time, so scanning is a matter of round trips
  rather than bandwidth, and running more of them at once is the most
  effective thing available. The old fixed value was 8.
- Copying a confirmed list of files over WebDAV no longer lists the
  destination first. The list already says exactly what to move, so that
  listing was the whole cost of the operation for nothing.

## 1.7.7

- Removed the `Config file not found - using defaults` notice from every
  WebDAV command. The backend is configured through the environment on
  purpose, so there is nothing to put in a config file, but rclone announces
  the absence each time it runs. It now gets an empty one to find.

## 1.7.6

- Fixed **Skip within this pair** and the global exclude list being ignored
  over WebDAV. The settings are written the way rsync reads them, where
  excluding `Anna` excludes the folder and everything in it. rclone reads a
  bare name as a file pattern, so those lines matched nothing and the folders
  synced anyway. Each pattern is now written in both forms.
- An include list over WebDAV blocked less than it should have, for the same
  reason.

## 1.7.5

- A WebDAV run no longer looks frozen while it works. Listing a share takes
  one request per directory, so the scan for one-sided items can run for
  minutes on a large tree. It now says what it is doing before it starts,
  and rclone reports progress every 30 seconds instead of having its output
  thrown away.
- Connection and transfer timeouts are set, so a connection that dies ends
  the run with something to read rather than waiting for ever.

## 1.7.4

- Fixed the completed WebDAV address not actually reaching rclone. The
  address was handed over before the checks that finish it ran, so the log
  showed the corrected address while the transfer used the original one and
  failed with the same complaint as before.

## 1.7.3

- The WebDAV address can now be just your Nextcloud address, such as
  `https://cloud.example.com`. The endpoint is always
  `<address>/remote.php/dav/files/<user>` and the app knows both halves, so
  it builds the rest and logs what it used. A full address still works, as
  does the older `/remote.php/webdav` one, which is the same base with the
  wrong tail.

## 1.7.2

- A WebDAV address that is not the files endpoint is now refused at the start
  of the run, naming the address it wants. Nextcloud also shows an older
  `/remote.php/webdav/` address that looks equally plausible and does not
  work, and rclone only said so once per folder pair.
- **Base folder** over WebDAV is a path inside the share, not a path on the
  server disk. A leading slash is stripped and the log says what was used.
- Every run now prints the remote each folder pair resolved to, so a wrong
  base folder is visible rather than something to infer from a failure.
- An address that is not https is refused; plain http is warned about.
- A failed transfer named rsync even when rclone was doing the work.

## 1.7.1

- Fixed WebDAV runs failing immediately with exit 1 and no explanation. The
  scan for deletion candidates reports a non-zero status whenever the two
  sides differ, which is the normal case, and that was ending the run before
  anything had been logged. The equivalent SSH scan never hit this because
  its output passes through a filter that masks the status.

## 1.7.0

- The remote side can now be a **WebDAV share**, which is how to reach
  Nextcloud. Set **How to connect** to WebDAV and give it the address, a
  username and an app password.
- Existing setups are untouched. **How to connect** defaults to SSH and
  nothing else changed for it.
- Reaching Nextcloud over WebDAV goes through Nextcloud itself, so it sees
  every change as it happens. Copying files into its storage directly needs
  an `occ files:scan` afterwards; this does not.
- WebDAV stores a password, unlike SSH. Use an app password rather than your
  account password. The app writes it to no file of its own, and the
  documentation is explicit about where it does live.
- **Remove leftover folders** has no effect over WebDAV. It exists for an
  rsync rule that does not apply there.

## 1.6.0

- Each review row now carries the first couple of filenames it stands for.
  A row reading "Work (1 file)" named a folder and hid the one thing worth
  knowing; it now names the file. Home Assistant renders them once the
  integration is on 1.5.0 or newer.

## 1.5.0

- Deletion candidates can now be reviewed folder by folder, and each folder
  can be kept or deleted rather than the whole list at once.
- Added **Keep**, which copies a candidate to the side that is missing it.
  Until now the only outcomes were deleting everything or leaving it, so
  anything left alone came back on every later run.
- The review list is grouped by folder, at the deepest level that still
  fits on screen. Grouping is only how it is shown: acting on a folder
  touches the recorded candidates inside it and nothing else.
- Deletions are re-checked as they are applied. Anything that has since
  appeared on the other side is left alone and reported.
- New `--resolve` option applies decisions recorded by Home Assistant.
- The state file gained `pending_groups`. The old flat `pending` list is
  still written, capped, so an older integration keeps working.

## 1.4.0

- Sync logs now say what happened in words instead of rsync codes. A line
  that read `<f..tp..... Photos/2020/IMG_4821.jpg` now reads
  `up   timestamp  Photos/2020/IMG_4821.jpg`, and every direction ends
  with a count: `[Photos up] 12 new, 3 updated, 1847 timestamp-only`.
- Added a warning when most of a run is timestamp-only. That means the
  destination is not keeping the times or permissions it is given, so
  unchanged files are re-sent on every run. The log now names the problem
  and points at the documentation instead of leaving it buried.
- Test runs are the main beneficiary: they always itemise, so they were
  the most likely place to meet the codes and the least likely place to
  want them.

## 1.3.1

- Added the Apache License 2.0. The repository previously shipped without
  a license file, which left its terms unstated. It is now the same
  license Home Assistant itself uses.

## 1.3.0

- The leftover-folder clean-up added in 1.2.2 is now a setting,
  **Remove leftover folders**, and it is off by default. With it off the
  sync behaves as it did before: a confirmed folder holding ignored files
  stays put, and the run says so and names it. Turn the setting on to
  have those folders removed for good.

## 1.2.2

- Actually fixed "cannot delete non-empty directory". The `--force` in
  1.2.1 did not help: rsync refuses because the leftover files are
  protected, not merely because the folder is not empty. A confirmed
  deletion now removes the folders rsync names, and only those. Excluded
  files anywhere else are still left alone.

## 1.2.1

- Fixed "cannot delete non-empty directory". A folder you confirmed for
  deletion was left behind whenever excluded clutter such as `.DS_Store`
  or `@eaDir` was still inside it, and it then came back asking for
  confirmation on every later run. Confirmed deletions now take that
  clutter with them. Excluded files elsewhere are still left alone.

## 1.2.0

- Added a **Deletion protection** setting. It is on by default and is
  what stops a sync removing anything on its own: items on one side
  only are listed and left for you to confirm. Turn it off and every
  run deletes as it goes, with nothing to confirm. Nothing changes
  unless you turn it off, and you can turn it back on at any time.

## 1.1.1

- Silenced a Supervisor deprecation warning by asking for
  `homeassistant_config` instead of `config`. The folder is pinned to
  the same place inside the app, so nothing else changes.

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
