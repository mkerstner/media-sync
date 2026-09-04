# Changelog

## 2.3.1

Applying a review of several hundred deletions took about an hour.

- **The list is now removed in one operation instead of one per file.** Each
  item had its own rclone or ssh invocation, which paid for process start,
  connection and authentication before it could send a single request - around
  five seconds each, whatever the server did. 695 items took an hour that the
  same server clears in a couple of minutes.
- The log says how many are going and names the first ten, rather than printing
  a line per file.
- If the removal reports errors, nothing from that batch is recorded as done,
  so those items stay in the review and can be tried again. Anything that did
  go is dropped from the list by the re-check on the next run, so retrying
  costs nothing.

## 2.3.0

Deleting files on the Home Assistant side was never reported, and in "both"
mode the deletion was undone before anything looked for it.

- **Every scan now runs before any transfer.** A run used to scan and sync one
  direction, then scan and sync the other. In "both" mode the pull therefore
  copied back whatever had just been deleted locally, and the push that
  followed found nothing missing and said nothing. Deletions on the *server*
  side were reported - the pull scans first - and then quietly put back by the
  push.
- **Items waiting for a decision are held out of the transfer.** The log has
  always said they were "left alone"; now they are. Without this, confirming
  "delete it on the server" would remove a file the same run had just restored
  locally, and it would come straight back as a candidate in the opposite
  direction.
- **A pair with an unanswered review is never skipped.** The quick check asks
  whether either side has changed since the last sync. Both sides can be
  perfectly quiet while a review is still outstanding, and a skipped pair
  reports nothing - so the notification was cleared by the next run and the
  candidates were lost.
- **Stamps written by an earlier version are retired.** One of them may say a
  pair is settled when a local deletion was silently reversed instead, so the
  first run after this update compares everything. That run will take as long
  as a full one.

## 2.2.0

- New Advanced setting **How deep to look for changes**, default 2. Until now,
  anything changing anywhere meant comparing the whole pair. The check now
  follows the change down the tree and compares only the folders that actually
  moved - so editing one file under one folder no longer means walking all the
  others.
- 0 keeps the old all-or-nothing behaviour. 1 narrows to the top-level folder,
  2 to the one below it, up to 10.
- Anything it cannot work out falls back to comparing that branch in full: a
  folder whose name cannot be decoded safely, a folder that has disappeared, an
  answer that did not look as expected. Being wrong costs a wider comparison,
  never a missed change.

## 2.1.0

- New `--full` option, which compares everything even where the server says
  nothing has changed. The quick check takes the server at its word, which is
  right except when the storage behind a WebDAV share is written to directly:
  Nextcloud does not always know, and will go on saying nothing has changed.
- Documented the two schedules worth running together - a check every few
  minutes, which is now cheap enough to be sensible, and a full comparison
  once a day to catch what the quick one cannot see.
- Fixed the link to the settings on the Info tab, which pointed at a file
  rather than the Documentation tab and so went nowhere.

## 2.0.2

- Brought the documentation on scan progress up to date. It described an error
  count climbing into the thousands and explained why not to worry about it -
  but that line has been filtered out of the log since 1.9.4, so it described
  something no longer visible. It now describes the line that is: the check
  count, and what its two numbers mean.

## 2.0.1

- A skipped folder pair now says when it last synced:
  `nothing has changed on either side since the last sync at 2026-09-04 16:12
  - skipped`. The time was already there, being the age of the record the
  check reads; it just was not shown, which left no way to tell a pair that
  syncs constantly from one that has quietly not run for a week.

## 2.0.0

**You will need to fill in the connection settings once after updating.** The
old ones cannot be carried over, for the reasons below. Note down your current
values before you update.

- The connection settings are now three sections instead of one list:
  **Connection** (which protocol, and the base folder), **SSH connection**, and
  **WebDAV connection**. Each says whether it applies, so there is no longer a
  screen of eight fields with nothing to say which half to fill in.
- **How to connect** now reads `SSH` and `WebDAV` rather than `ssh` and
  `webdav`. An app can only label a choice by changing the value itself,
  which is part of why the old settings do not carry over.
- The SSH fields moved from `source.remote_host` to `ssh.host`, and likewise
  for the WebDAV ones. Anything set in YAML or an automation needs the new
  names.

## 1.10.0

- New Advanced setting **Skip folders that have not changed**, on by default
  and only used over WebDAV. Nextcloud gives a folder a new tag whenever
  anything inside it is updated, and the change carries up to the parents, so
  one question against the top of a pair answers whether anything below it
  moved. A run with nothing to do now finishes in seconds instead of listing
  every folder to find that out.
- The local side is checked as well, so a change made in Home Assistant is
  still picked up. Deletions count: removing a file moves the time on the
  folder that held it.
- Anything uncertain counts as changed - an unreadable tag, a pair that has
  never synced - so the cost of being wrong is a slow run, never a missed one.

## 1.9.10

- **Confirming a deletion in the review now actually deletes.** Every run
  records its state as "running" before doing anything, and at that moment the
  list of candidates it has found is empty - which was taken to mean nothing
  is pending, and cleared the file holding the previous run findings. A
  `--resolve` run therefore deleted its own input before reading it, reported
  "no recorded candidates left to act on", and discarded the decisions it had
  been started to carry out.
- The file is now only cleared by a run that reached the end and found
  nothing. A run that is still going, or that failed, leaves it alone.

Deletion protection does not need to be turned off to confirm a deletion. It
never did - the review was simply unable to act.

## 1.9.9

- The Info tab now describes both ways to connect. It still said the app works
  with any server reachable over SSH and that there is no password to store,
  which stopped being the whole story when WebDAV arrived in 1.7.0.
- It also says what to check before choosing WebDAV: a Nextcloud folder that
  is external storage is reached better through the storage itself.

## 1.9.8

- Scan progress says something again. 1.9.4 compressed it to one line, but
  the one-line form carries only the transfer counters, which a scan never
  touches - so it reported `0 B / 0 B, -, 0 B/s, ETA -` every thirty seconds
  and nothing else. The line now shown is the check count, which is the one
  that moves: `Checks: 5114 / 5114, 100%, Listed 11963`.
- The rest of the block stays out of the log: nothing is transferred during a
  scan, and its error count is the number of differences found.

## 1.9.7

- Corrected the advice on **Parallel WebDAV requests**. Raising it is right
  when the folders are Nextcloud own storage and wrong when they are external
  storage: each request there opens a connection to whatever is behind it,
  and those are limited - a Hetzner Storage Box allows ten. Asking for more
  than the limit makes requests fail for want of a connection, which looks
  like a folder that lists and then cannot be opened.
- 1.8.0 raised the default to 16 and recommended going higher, which is above
  that limit and made matters worse for anyone in that position.

## 1.9.6

- Withdrew the advice to normalise filenames with `convmv`. It rested on a
  diagnosis that does not hold: Nextcloud own clients read those names
  without trouble, so the names were never the problem. Renaming files in
  bulk is a large thing to do on a guess, and this told people to do it.
- A folder that lists and then cannot be opened now points at the external
  storage question instead, which is where that failure actually comes from.

## 1.9.5

- Documented when **not** to use WebDAV. A Nextcloud folder that is external
  storage is a view onto something else - SFTP, SMB, S3 - and syncing it over
  WebDAV routes every listing through Nextcloud into that other system, then
  moves every byte twice. Point the app at the real storage instead. Over SFTP
  that is the SSH transport, and Nextcloud goes on serving the same files
  because it is the same filesystem.

## 1.9.4

- The scan reports progress on one line instead of a five-line block every
  thirty seconds.
- Documented the error count that appears while scanning. The tool underneath
  counts every one-sided file as an error, so the number is the count of items
  found rather than a sign of trouble, and "retrying may help" does not apply
  to it.

## 1.9.3

- Reverted the change in 1.9.2, which was wrong. `file not in <somewhere>`
  is not a failure: rclone logs it for every file that is on one side and not
  the other, which is exactly what the delete scan is looking for. Treating
  those as unreadable folders held back every deletion candidate there was,
  so the review would have shown almost nothing. 1.9.1 already covers the
  real case, where a folder cannot be listed at all.
- Those lines no longer reach the log either. There is one per difference,
  thousands on a first run, and each says what the candidate list already
  says while reading like something went wrong.

## 1.9.2

- Widened the guard added in 1.9.1. It recognised a folder the server could
  not list, but not the other shape the same problem takes: the server names
  an item and then refuses to resolve it, once per item, with `file not in
  webdav root`. Those items were still being offered for deletion.
- The folder holding an unresolvable item is now held back as a whole,
  including items it did not complain about, because a listing that went
  wrong part way cannot be trusted for the rest of it.
- An unresolvable name directly at a pair root no longer holds back the
  entire pair.

## 1.9.1

- A folder that cannot be read is no longer treated as an empty one. Listing
  it fails, everything inside it is reported as missing from the other side,
  and the review then offered those files for deletion - files that are on the
  server the whole time. The folders rclone or rsync could not read are now
  named in the log, and nothing inside them is proposed for deletion until
  they can be read again.
- The re-check that runs before a confirmed deletion applies the same rule, so
  a decision made earlier cannot delete through a folder that has since become
  unreadable.
- Fixed applying review decisions over WebDAV. The remote side was addressed
  as `user@host:` there as well, which is an SSH address, so keeping or
  deleting a reviewed item could not find the server.

## 1.9.0

- A run that fails on individual items now finishes the rest of them. It names
  what it could not handle, carries on to the remaining folder pairs, and
  reports the run as failed at the end. Until now the first unreadable path
  stopped everything, so one file could block a whole library.
- A failure that cannot name any item - a wrong address, a refused login -
  still ends the run immediately, because there is nothing to carry on with.
- The last successful sync is no longer recorded when items failed.

## 1.8.2

- Added `.DAV/` to the default excludes. WebDAV clients leave that folder
  behind as their own bookkeeping, so it exists on one side, never the other,
  and turns up as a deletion candidate for ever.

## 1.8.1

- Excluded folders are now genuinely skipped over WebDAV instead of being
  walked and then discarded. rclone only avoids descending into a folder for
  a rule that ends in a slash; the rules written in 1.7.6 left out that form,
  so an excluded folder still cost a full listing and could still report
  errors from inside itself.

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
