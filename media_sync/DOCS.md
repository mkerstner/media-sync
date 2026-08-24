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

Everything travels over SSH — the same encrypted connection SFTP and SCP use.

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

## Settings

The options screen is grouped into sections. In YAML the same grouping applies,
so a setting is written as `source.remote_host` rather than `remote_host`.

### Source server

| Setting | What it does |
| --- | --- |
| `remote_host` | Hostname or IP of the server. |
| `remote_user` | The account to log in as. |
| `remote_port` | SSH port. Usually `22`; a Hetzner Storage Box uses `23`. |
| `remote_base` | Folder the remote paths are counted from. Leave empty to start from the login's home folder. |

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

### Before anything is deleted

A deletion is re-checked at the moment it is applied. If a file has since
appeared on the other side, it is no longer missing, so it is left alone and
the log says how many were skipped. Decisions can therefore sit unanswered
safely.

The full candidate list lives in `/config/media_sync/pending.tsv`, and your
decisions arrive as `/config/media_sync/decisions.tsv`. Both are plain text.

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
