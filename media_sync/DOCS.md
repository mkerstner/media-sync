# Media Sync

Keeps your media library and a remote server in sync, in both directions.

Each run compares the two sides and copies whichever copy of a file is newer.
Nothing is ever deleted without your say-so: anything that exists on only one
side is listed and left alone, and the Media Sync integration asks you before
removing it.

It works with any server you can reach over SSH — a NAS, a VPS, a rented
storage box. A Hetzner Storage Box is used as the example below, but nothing
here is specific to it.

There are three ways to start a sync, and they all do the same thing:

- **From the UI.** Install the Media Sync integration and you get buttons and
  status you can put on a dashboard. This is the easy way.
- **From an automation.** The integration adds actions you can call on a
  schedule or from any trigger, with a choice of direction.
- **From a terminal.** `media-sync.sh` runs on its own, with no Home Assistant
  involved at all. See the last section.

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
3. Start it once. It creates a key at `/ssl/media_sync/remote.key` and prints
   the public half to its log.
4. Give that public key to your remote server, so it will let Home Assistant in
   without a password. On most servers you append it to `~/.ssh/authorized_keys`.
5. Fill in the settings below, then install the **Media Sync** integration to
   get buttons, status and the deletion confirmation.

## Settings

| Setting | What it does |
| --- | --- |
| `log_level` | How much detail to print. `info` by default; set `debug` when something is not behaving. |
| `remote_host` | Address of the remote server. |
| `remote_user` | Account to log in as. |
| `remote_port` | SSH port. Usually `22`; a Hetzner Storage Box uses `23`. |
| `remote_base` | Folder on the server that the entries in `folders` are relative to. Leave empty to start from the login's home folder. |
| `direction` | `both` compares the two sides and keeps whichever file is newer. `pull` only brings files down, `push` only sends them up. |
| `folders` | Which folders to keep in sync. See below. |
| `include_dirs` | If you fill this in, only these top-level folders are synced. Leave empty for everything. |
| `exclude_patterns` | Things to never sync, such as system clutter and temporary files. |

### `folders`

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

### Patterns

`include_dirs` and `exclude_patterns` accept the same kind of patterns rsync
uses. A leading `/` pins a pattern to the top of that folder, otherwise it
matches at any depth. A trailing `/` matches folders only.

Anything you exclude is also protected from deletion, so confirming a deletion
will never sweep away something you asked to be ignored.

## Logs

Open the **Log** tab of the app. Because the app runs once and stops, it also
replays the last 50 lines of recent activity before each run, so you see how
you got here rather than just the run in front of you.

Both halves write to the same file, `/config/media_sync/media-sync.log`:

```
2026-08-16 15:40:02  action  sync (both directions) requested by Matthias
2026-08-16 15:40:03  run     started
2026-08-16 15:40:03 direction: both
2026-08-16 15:40:05 [Media pull] 2 item(s) present in the destination but not the source:
2026-08-16 15:52:10 Done
2026-08-16 15:52:11  run     finished
2026-08-17 03:30:00  action  sync (both directions) requested by an automation or script
```

`action` lines come from Home Assistant and record what was asked for and by
whom. `run` lines bracket each run, and everything between them is the sync
itself.

The file is trimmed to its last 2000 lines each time the app starts, so it
cannot grow without limit — worth knowing because `/config` is included in
your backups.

## How the two halves talk

The app does one run and stops. The integration leaves the options for the next
run in `/config/media_sync/request.json`, starts the app, and reads the outcome
from `/config/media_sync/state.json`.

Anything that would have been deleted is also written out in readable form to
`/config/media_sync/deletions.txt`.

## Running it from a terminal

To trigger the app, drop a request file and start it. Home Assistant assigns
the app a slug based on the repository it came from, so look it up rather than
guessing:

```
mkdir -p /config/media_sync
echo '{"args":["--dry-run"]}' > /config/media_sync/request.json
ha addons list          # find the slug ending in media_sync
ha addons start <slug>
```

To sync without involving the app at all, copy `media-sync.sh` somewhere such
as `/config/scripts/` and pass the same settings as environment variables:

```
REMOTE_HOST=storage.example.com REMOTE_USER=username REMOTE_PORT=22 \
REMOTE_KEY=/ssl/media_sync/remote.key \
  sh /config/scripts/media-sync.sh --dry-run
```

Options: `--dry-run` to see what would happen, `--scan-only` to look for
deletions without copying anything, `--pull-only` and `--push-only` to go one
way, `--no-delete-check` to skip the deletion scan, and `--yes` to go ahead and
delete without being asked.
