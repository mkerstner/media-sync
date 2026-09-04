# Media Sync

Keeps your media library and a remote server in sync, in both directions.

Each run compares the two sides and copies whichever copy of a file is newer.
Nothing is deleted unless you ask for it. By default, anything that exists on
only one side is listed and left alone, and the Media Sync integration asks you
before it goes. That protection can be turned off if you would rather each run
just got on with it.

It works with any server you can reach over SSH — a NAS, a VPS, a rented
storage box.

There are three ways to start a sync, and they all do the same thing:

- **From the UI.** Install the Media Sync integration and you get buttons and
  status you can put on a dashboard. This is the easy way.
- **From an automation.** The integration adds actions you can call on a
  schedule or from any trigger, with a choice of direction and a dry-run
  option. Worked examples are in the
  [integration README](https://github.com/mkerstner/media-sync-integration#automations).
- **From a terminal.** The app drops a copy of the sync script at
  `/config/scripts/media-sync.sh`, which runs on its own with no Home
  Assistant involved. See the last section.

However you start it, the outcome is recorded in the same place, so a run you
kick off by hand still shows up in Home Assistant.

## Is it secure?

Everything travels over an encrypted connection, whichever protocol you pick:
SSH, the same one SFTP and SCP use, or HTTPS for WebDAV.

### Over SSH

- **Your files are encrypted on the way.** Nothing is sent in the clear between
  Home Assistant and the remote server.
- **No passwords, anywhere.** The app logs in with a key pair. The private half
  is created on your own machine, stays in `/ssl/media_sync/` where only root
  can read it, and never appears in the interface, the logs, or a diagnostics
  download. Only the public half is given to the server.
- **The server's identity is pinned.** The first connection records the
  server's fingerprint in `/ssl/media_sync/known_hosts`. If it ever changes,
  the sync stops instead of handing your files to whatever answered. That trust
  is established on the first connection, so do the setup on a network you
  trust.
- **Password login is switched off** for these connections, so a run can never
  quietly fall back to something weaker, or sit there waiting on a prompt.

### Over WebDAV

WebDAV has no equivalent of a key pair, so this one **does** store a password.
That is a real difference from SSH, and worth knowing before you choose it.

- **Use an app password, never your account password.** In Nextcloud, create
  one under **Settings, Security, Create new app password**. It can be revoked
  on its own without changing your login, and it keeps working when two-factor
  authentication is on.
- **Use an https:// address.** WebDAV over plain http would send the password
  and your files in the clear.
- **The app writes the password to no file of its own.** It is handed to the
  transfer tool through the environment, in the obscured form that tool
  expects, so it appears in no command line and no config file. It does live in
  the app settings, which the Supervisor stores, and that is the honest limit
  of this.
- **It never reaches the logs** or a diagnostics download.

## Setup

1. Go to **Settings → Apps → ⋮ → Repositories** and add
   `https://github.com/mkerstner/media-sync`.
2. Find **Media Sync** in the store and install it.
3. Start it once. It creates a key at `/ssl/media_sync/remote.key`, drops a
   copy of the sync script at `/config/scripts/media-sync.sh`, and prints
   the public half to its log.
4. Give that public key to your remote server, so it will let Home Assistant in
   without a password. On most servers you append it to `~/.ssh/authorized_keys`.
5. Fill in the settings below, then install the **Media Sync** integration to
   get buttons, status and the deletion confirmation.

## Connecting to Nextcloud, or any WebDAV share

Set **How to connect** to WebDAV and fill in three fields.

**WebDAV address.** The address of your Nextcloud is enough:

```
https://cloud.example.com
```

The endpoint is always `<address>/remote.php/dav/files/<user>`, and the app
knows both halves, so it fills in the rest and says in the log what it used.
Pasting the full address that Nextcloud prints at the bottom left of its Files
page works just as well.

Use `https://`, never `http://`.

**WebDAV username.** Your account name on that server.

**WebDAV password.** Create an app password rather than using your account
password: **Settings, Security, Create new app password**. Nextcloud shows it
once, so copy it straight into the app. An app password can be revoked on its
own, and it keeps working with two-factor login.

The folder pairs work exactly as they do over SSH, with one difference worth
being deliberate about: **Base folder** is a path *inside the share*, not a
path on the server disk. Over SSH it might be `/home/data/nas`; over WebDAV
that same setting means a folder called `home/data/nas` in your Nextcloud
Files. Usually it should be empty, or the name of one folder.

A leading slash is meaningless here, so the app strips it and says in the log
what it settled on. Every run also prints the remote each pair resolved to, so
a wrong base folder shows up as a line you can read rather than a failure you
have to interpret.

### First check what the folder actually is

Open **Settings, Administration, External storage** in Nextcloud and see
whether the folder you are about to sync is listed there.

If it is, do not sync it over WebDAV. An external storage folder is not stored
by Nextcloud - it is a view onto something else, reached over SFTP, SMB, S3 or
similar. Syncing it over WebDAV means every listing becomes an HTTP request
that Nextcloud turns into operations against that other system, and every byte
travels twice:

    Home Assistant -> WebDAV -> Nextcloud -> SFTP -> the real storage

Point this app at the real storage instead. Over SFTP that is the SSH
transport, which is faster by a wide margin, preserves timestamps and
permissions properly, and needs no password. Nextcloud goes on serving the
same files to your other devices, because it is the same filesystem either
way - nothing about your Nextcloud setup has to change.

It also avoids a class of failure that belongs to the middle layer rather than
to either end. Names that a filesystem stores in one Unicode form are not
always handed back by Nextcloud's external storage in the form it will accept
again, so a folder lists successfully and then cannot be opened. Reaching the
storage directly, there is no translation to get wrong.

WebDAV is the right choice when the files really are Nextcloud's own.

### Why this is the right way to reach Nextcloud

Syncing files into Nextcloud's storage directly, behind its back, leaves its
database unaware of them until someone runs `occ files:scan`. WebDAV goes
through Nextcloud itself, so it sees every change as it happens. There is
nothing to rescan.

### What differs from SSH

- **Remove leftover folders** does nothing. It exists because rsync refuses to
  delete a directory that still holds excluded files; WebDAV transfers have no
  such rule.
- **Per-file log lines look different.** The plain-word rendering described
  under Logs applies to the SSH transport. WebDAV runs report in the transfer
  tool's own wording, which is already readable, and the end-of-run counts are
  not produced.
- **Large uploads.** Nextcloud chunks uploads at 10 MiB by default. If you move
  large video files regularly, raising that on the Nextcloud side improves
  throughput. That is a Nextcloud setting, not one this app can change.

Everything else is the same: both directions, newest wins, test runs, include
and exclude rules, deletion protection, and the folder-by-folder review.

### What the scan reports while it runs

A WebDAV scan has to ask the server about one folder at a time, so on a large
share it runs for a while. Every thirty seconds it prints where it has got to:

```
Checks:              5114 / 5114, 100%, Listed 11963
```

**Checks** is how many items have been compared, **Listed** how many the server
has named so far. Both climb until the scan finishes. Nothing is transferred
while scanning, so there is no byte counter.

Two things the underlying tool also reports are left out of the log, because
neither means what it says. It counts every file that exists on one side and
not the other as an error - that is how it signals "these two are not
identical" to whatever called it - and prints one such line per item, plus a
running total, plus the words "retrying may help". On a first run that total
reaches the thousands, and every one of those items is the answer the scan was
asked for rather than a problem with it. They are already on their way to the
review.

A real failure is not filtered. It names a folder and says it could not be
read, and it is worth reading.

### When some items cannot be transferred

A run that fails on individual items now finishes the rest of them, names what
it could not handle, and reports the run as failed at the end. One unreadable
path used to stop every other file, and every later folder pair, from syncing
at all.

Over WebDAV, the shape to look out for is a folder that lists successfully and
then cannot be opened: `error reading source directory: directory not found`
against a folder you can see perfectly well in a browser.

Check first whether that folder is **external storage** rather than storage of
Nextcloud's own - see above. A name that arrives through that layer is not
always handed back in the form it will be accepted in again, which is exactly
what a folder that lists and then vanishes looks like. Syncing the underlying
storage directly avoids the translation entirely, and is faster besides.

Do not start renaming files over this. Nextcloud's own clients read these
names without trouble, so the names are not the problem, and normalising them
in bulk is a large change made on a guess.

### If a WebDAV sync is slow

WebDAV has no way to ask for a whole tree at once, so a share is listed one
folder at a time. That makes scanning a matter of round trips rather than
bandwidth, and the things that help are the ones that reduce or overlap them:

- **Skip folders that have not changed**, under Advanced and on by default,
  is the one that helps most when there is nothing to do. Nextcloud gives a
  folder a new tag whenever anything inside it is updated, and the change
  carries up to the parent folders, so one question against the top of a pair
  answers whether anything below it moved. A run with nothing to sync then
  finishes in seconds rather than walking the tree to discover that.

  The local side is checked too, by looking for anything modified since the
  last sync - which catches deletions as well, because removing a file moves
  the time on the folder that held it.

  Anything uncertain counts as changed. A tag that cannot be read, a pair that
  has never synced, a folder that is missing: all of those fall back to the
  full scan, so the cost of being wrong is a slow run rather than a missed
  one.

- **How deep to look for changes**, under Advanced, decides what happens once
  something *has* changed. At 0 the whole pair is compared, however small the
  change was. At 1 the folders below the pair root are asked individually and
  only the ones that moved are compared; at 2 the level below that, and so on.
  The default is 2.

  Each level costs one request per changed folder at that level, and saves
  comparing everything that did not change. On a share where one folder gets
  edited and the rest sit still, this is the difference between comparing one
  folder and comparing all of them.

  Deeper is not automatically better: each level asks more questions, and past
  a point asking costs more than looking. Anything it cannot work out - a name
  it will not risk decoding, a folder that vanished, an answer it did not
  expect - falls back to comparing that branch in full.

- **Parallel WebDAV requests**, under Advanced, decides how many of those
  round trips happen at once. It defaults to 16.

  Raise it if the folders really are Nextcloud own storage. **Lower it, a
  long way, if they are external storage** - see above. Each request there
  makes Nextcloud open a connection to whatever is behind it, and those are
  usually limited: a Hetzner Storage Box allows ten at once, and other
  providers are similar. Ask for more than the limit and requests start
  failing for want of a connection, which surfaces as a folder that lists and
  then cannot be opened. Try 2 or 3 and see whether the failures stop.
- **Exclude what you do not sync.** Anything not excluded is walked in full,
  every run, even if nothing in it ever changes.
- **Point the pair at a smaller folder**, or use the include list, rather than
  pairing with the root of a large share.
- **Sync one direction at a time** while you are measuring. Each direction
  walks the tree independently.
- On the Nextcloud side, a single folder holding many thousands of entries is
  slow to list no matter what this app does. Splitting it up helps more than
  any setting here.

## Settings

The options screen is grouped into sections. In YAML the same grouping applies,
so a setting is written as `ssh.host` rather than `host`.

### Connection

| Setting | What it does |
| --- | --- |
| `source.protocol` | `SSH` or `WebDAV`. Decides which of the two sections below is used; the other is ignored. |
| `source.remote_base` | Folder the remote paths are counted from. Leave empty to start at the top. Over SSH that is the login's home folder; over WebDAV it is a folder inside the share, never a path on the server's disk. |

### SSH connection

Used only when `source.protocol` is `SSH`.

| Setting | What it does |
| --- | --- |
| `ssh.host` | Hostname or IP of the server. |
| `ssh.user` | The account to log in as. |
| `ssh.port` | SSH port. Usually `22`; a Hetzner Storage Box uses `23`. |

### WebDAV connection

Used only when `source.protocol` is `WebDAV`.

| Setting | What it does |
| --- | --- |
| `webdav.url` | The address of your Nextcloud. The rest of the WebDAV path is worked out from the username. |
| `webdav.user` | The account name on that server. |
| `webdav.password` | An app password, not your account password. |

### Syncing

| Setting | What it does |
| --- | --- |
| `direction` | `both` compares the two sides and keeps whichever file is newer. `pull` only brings files down, `push` only sends them up. |
| `delete_protection` | **On by default.** Nothing is deleted while it is on; items on one side only are listed for you to confirm. Turn it off and every run deletes as it goes. |
| `force_removal` | **Off by default.** A confirmed folder that still holds ignored files cannot be removed by the sync and keeps coming back. Turn this on to remove those folders for good. |
| `dry_run` | Report what would happen without changing anything. Applies to every run while it is on, including ones started from Home Assistant. |
| `include_dirs` | If you fill this in, only these top-level folders are synced. Leave empty for everything. |
| `exclude_patterns` | Things to never sync, such as system clutter and temporary files. |

### Advanced

| Setting | What it does |
| --- | --- |
| `log_level` | How much detail the app itself prints. `info` by default; set `debug` when something is not behaving. |
| `sync_log_verbosity` | How much the sync itself prints. See below. |
| `log_keep_days` | How many days of activity to keep in the shared log. `14` by default. |

### Folders

`folders` sits outside the sections. It is a list of entries, which is already
as deeply nested as the Supervisor allows, so it cannot live inside one.

```yaml
folders:
  - name: Media
    remote: Media
    local: /media/Media
    exclude: ""
  - name: Documents
    remote: "."
    local: /media/Documents
    exclude: /Media/
```

- `remote` is relative to `remote_base`. Use `"."` for the whole of it.
- `exclude` is a comma-separated list that applies to this entry only. That is
  how the `Documents` entry above keeps its hands off `/Media`.

### `sync_log_verbosity`

How much the sync prints while it runs. Everything it prints ends up in the
Log tab and in the shared log file.

| Value | What you see |
| --- | --- |
| `quiet` | Nothing but errors. |
| `summary` | Totals at the end of each folder: how many files moved, how much data. The default. |
| `files` | One line per file transferred, plus the totals. |
| `changes` | Every file, in plain words: whether it was added, updated, or only re-stamped. See [What the file lines mean](#what-the-file-lines-mean). |
| `progress` | Every file, plus how far along the run is. |
| `debug` | Everything, including why rsync decided to transfer each file. |

`progress` shows a live percentage and transfer rate, which is useful while
watching the Log tab during a big first sync. It also writes far more than the
other settings, so the shared log fills up and gets trimmed sooner. `files` is
usually the better everyday choice if you want to see what moved, and
`changes` when you want to know why something was copied again.

A dry run always itemises every change regardless of this setting — that is
the point of a dry run.

### Patterns

`include_dirs` and `exclude_patterns` accept the same kind of patterns rsync
uses. A leading `/` pins a pattern to the top of that folder, otherwise it
matches at any depth. A trailing `/` matches folders only.

Excluded things are protected from deletion on their own account: a
confirmed deletion never goes hunting for them elsewhere in the tree.

That protection has a side effect. A folder you confirmed for deletion
cannot be removed while ignored files are still sitting inside it, so it
survives and comes back asking for confirmation on the next run. Turning
on `force_removal` clears those folders out, and only those.

## Logs

Open the **Log** tab of the app. Because the app runs once and stops, it also
replays the last 50 lines of recent activity before each run, so you see how
you got here rather than just the run in front of you.

Both halves write to the same file, `/config/media_sync/media-sync.log`:

```
2026-08-21 13:36:02  action  sync (both directions) requested by Matthias
2026-08-21 13:36:03  run     started
2026-08-21 13:36:05 [Documents pull] 3 item(s) present in the destination but not the source:
      Notes/draft.md
      Notes/old.md
      x.txt
2026-08-21 13:36:51 [Documents pull] not confirmed - 3 item(s) left alone
2026-08-21 13:40:14 Done
2026-08-21 13:40:14 5 item(s) exist on one side only and were left alone:
      3 in [Documents pull]
      2 in [Media push]
2026-08-21 13:40:14 Full list: /config/media_sync/deletions.txt
2026-08-21 13:40:14 Confirm or dismiss them from the repair notification in Home Assistant.
2026-08-21 13:40:15  run     finished
```

`action` lines come from Home Assistant and record what was asked for and by
whom. `run` lines bracket each run, and everything between them is the sync
itself.

Entries older than `log_keep_days` are removed each time the app starts, and an
entry keeps its indented detail lines with it. As a backstop the file is also
capped at 1 MB — past that, what is there is moved aside to `media-sync.log.1`
and a fresh log is started. Both matter because `/config` is included in your
backups.

### What the file lines mean

With the sync log detail set to **Changes**, and on every test run, each file
that moved gets a line:

```
  up   new        Photos/2022/IMG_4821.jpg
  down updated    Documents/notes.md
  up   timestamp  Photos/2020/20200602_151740.jpg
       new folder Photos/2022/
       deleted    Photos/old/thing.jpg
```

`up` means the file went to the remote server, `down` means it came from there.

| Word | Meaning |
| --- | --- |
| `new` | Did not exist on the other side |
| `updated` | Contents differ, so the file was copied |
| `timestamp` | Contents are identical - only the modification time or permissions differed |
| `metadata` | Nothing was copied, only attributes were adjusted |
| `new folder` | A directory was created |
| `deleted` | Removed from the destination |

Each direction then ends with a count:

```
[Photos up] 12 new, 3 updated, 1847 timestamp-only, 1 deleted
```

### When everything says "timestamp"

If most of a run is `timestamp` lines, your files are being re-sent even though
their contents already match. Nothing is lost or corrupted, but every run moves
far more data than it needs to.

It means the destination is not keeping the modification times or permissions it
is handed, so the next run finds a mismatch and sends the file again. The usual
causes:

- The destination filesystem cannot represent them - an SMB, FAT or exFAT mount
  is the common one.
- The account on the remote server is not allowed to set ownership or
  permissions.
- One side was first populated by another tool that did not preserve times.

The fix is on the destination, not in the app: mount the share with options that
preserve timestamps, or use a filesystem and account that can. Until then the
sync stays correct - it is only wasteful.

## Reviewing what was left alone

When a file sits on one side but not the other, the app cannot tell whether it
was deleted there or added here, so it leaves it alone and records it. Home
Assistant then asks you what to do.

There are two answers, not one:

| Choice | What happens |
| --- | --- |
| **Keep** | The file is copied to the side that is missing it |
| **Delete** | The file is removed from the side that still has it |

Keeping is what actually clears an item. Before this existed the only options
were "delete everything" or "leave it", and anything left came back on the
next run for ever.

### Why the review is by folder

A run can turn up thousands of candidates, which nobody can review one by one.
They almost always sit in a handful of folders, so the app groups them:

```
Photos/2019/jan   412 files   on Home Assistant only
Photos/2020        38 files   on Home Assistant only
Notes               2 files   on the server only
```

The grouping adapts. It starts as specific as it can and only rolls up to a
shallower level when there would otherwise be too many rows.

Each row also carries the first couple of filenames it stands for, because a
folder name says nothing when it represents a single file.

**Grouping is only how the list is shown.** Deciding on a folder acts on the
recorded candidates inside it and nothing else - a folder holding two
candidates usually holds hundreds of correctly synced files, and those are
never touched.

### While a decision is outstanding

A candidate is left out of the transfer entirely until you answer for it.

That matters most in **both** directions. A file you deleted on the Home
Assistant side is still on the server, so a plain merge would copy it back -
and then, if you confirmed the deletion, remove it from the server while the
copy it had just restored stayed behind. The same file would come round again
as a candidate in the opposite direction, run after run. Holding it means
neither side moves until you say which one is right.

A pair with an open review is also never skipped by the quick change check.
Both sides can be perfectly still while the question is unanswered, and a
skipped pair reports nothing at all - so the notification would clear itself
and the list would be gone.

### Before anything is deleted

A deletion is re-checked at the moment it is applied. If a file has since
appeared on the other side, it is no longer missing, so it is left alone and
the log says how many were skipped. Decisions can therefore sit unanswered
safely.

The full candidate list lives in `/config/media_sync/pending.tsv`, and your
decisions arrive as `/config/media_sync/decisions.tsv`. Both are plain text.

## Two schedules worth having

Most setups want two different things from a schedule, and they are best kept
separate.

### Little and often

A check every few minutes, to pick up whatever has just changed.

With **Skip folders that have not changed** on, a check that finds nothing to
do costs one question to the server rather than a walk of the whole share, so a
short interval is affordable in a way it was not before. Set it under the
integration's **Configure** screen - *Run a check every 5 minutes* - and leave
the direction on pull if you mainly consume what the server holds.

Watch the **Last run duration** sensor for the first few. If a check regularly
takes longer than the gap between checks, the interval is too short for the
size of the share.

### Big and rare

A full comparison once a day, to catch anything the quick check could not see.

The quick check trusts the server when it says a folder has not changed. That
is almost always right, and there is one case where it is not: if the storage
behind a WebDAV share is written to directly - by something other than
Nextcloud - the server may not know, and will keep saying nothing has changed.
A run with `--full` ignores that answer and compares everything.

```yaml
automation:
  - alias: "Full media sync overnight"
    triggers:
      - trigger: time
        at: "03:30:00"
    actions:
      - action: media_sync.sync
        data:
          config_entry: 01JQ8ZK4M7WXYZ0123456789AB
          direction: both
          full: true
```

Expect it to take as long as a first run, because that is what it is doing.
Overnight is the right slot for it.

### Which to use

| | Quick check | Full sync |
| --- | --- | --- |
| How often | Every few minutes | Daily, or weekly |
| Costs | One request when nothing changed | A full walk, every time |
| Notices | Anything Nextcloud knows about | Everything, including changes made behind Nextcloud's back |

Running both is the point: the frequent one keeps things current, the rare one
makes sure the frequent one has not been quietly missing something.

## How the two halves talk

The app does one run and stops. The integration leaves the options for the next
run in `/config/media_sync/request.json`, starts the app, and reads the outcome
from `/config/media_sync/state.json`.

Anything that would have been deleted is also written out in readable form to
`/config/media_sync/deletions.txt`.

## Running it from a terminal

The app keeps a runnable copy of the sync script at
`/config/scripts/media-sync.sh`. It is written the first time the app starts
and refreshed on every start after that, so it is always the same version the
app itself runs. That also means **your changes to that file are overwritten** —
copy it under another name if you want to customise it.

To sync without involving Home Assistant at all, run it and pass the settings
as environment variables:

```
REMOTE_HOST=storage.example.com REMOTE_USER=username REMOTE_PORT=22 \
REMOTE_KEY=/ssl/media_sync/remote.key \
  sh /config/scripts/media-sync.sh --dry-run
```

Options: `--dry-run` to see what would happen, `--scan-only` to look for
deletions without copying anything, `--pull-only` and `--push-only` to go one
way, `--no-delete-check` to skip the deletion scan, and `--yes` to go ahead and
delete without being asked. `-q`, `-v`, `--changes` and `--progress` override
`sync_log_verbosity` for that one run.

To trigger the app instead, so it uses the settings you configured and reports
back to Home Assistant, drop a request file and start it. Home Assistant
assigns the app a slug based on the repository it came from, so look it up
rather than guessing:

```
mkdir -p /config/media_sync
echo '{"args":["--dry-run"]}' > /config/media_sync/request.json
ha addons list          # find the slug ending in media_sync
ha addons start <slug>
```
