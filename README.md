# Media Sync

Keeps your media library and a remote server in sync, in both directions, and
asks before it deletes anything.

Works with any server you can reach over SSH — a NAS, a VPS, a rented storage
box. Everything travels over an encrypted SSH connection, using a key the app
creates for itself, so there is no password to store.

This repository holds the **Media Sync app**, which does the actual syncing.
Its companion, the
[Media Sync integration](https://github.com/mkerstner/media-sync-integration),
adds buttons, status and the deletion confirmation to Home Assistant.

## Install

1. Go to **Settings → Apps → ⋮ → Repositories** and add:

   ```
   https://github.com/mkerstner/media-sync
   ```

2. Find **Media Sync** in the store and install it.
3. Start it once. It creates an SSH key and prints the public half to its log.
4. Give that public key to your remote server.
5. Fill in its settings — which server, which folders.

Full details in [the app documentation](media_sync/DOCS.md).

Then install the [integration](https://github.com/mkerstner/media-sync-integration)
to drive it from Home Assistant.

## Publishing prebuilt images

By default the Supervisor builds the app from the `Dockerfile` on each user's
own machine. That always works, but it takes a few minutes per install.

To have users pull a ready-made image instead:

1. Push a commit or publish a release so `.github/workflows/build.yaml` runs,
   and check in the **Actions** tab that all five architectures succeeded.
2. Open <https://github.com/mkerstner?tab=packages>. Each `media-sync-<arch>`
   package is **private** when first published — open it, then
   **Package settings → Change visibility → Public**. The Supervisor pulls
   anonymously, so a private package fails with `403 denied`.
3. Confirm an anonymous pull works, from a machine not logged in to ghcr.io:

   ```
   docker manifest inspect ghcr.io/mkerstner/media-sync-aarch64:1.0.0
   ```

4. Only then add this line to `media_sync/config.yaml`:

   ```yaml
   image: ghcr.io/mkerstner/media-sync-{arch}
   ```

The image tag comes from `version:` in `config.yaml`, so **every version bump
needs its images published before users update**, or the install asks for a tag
that does not exist.

## Starting a sync

Three ways, all doing the same thing:

- **From the UI** — press a button, or put one on a dashboard.
- **From an automation** — call the `media_sync.sync` action, optionally
  choosing a direction.
- **From a terminal** — the sync script runs on its own, with no Home
  Assistant involved.

However you start it, the outcome is recorded in the same place, so a run you
kick off by hand still shows up in Home Assistant.

## About deletions

When a file is on one side but not the other, there is no way to tell whether
it was deleted there or added here. So nothing is deleted automatically. The
items are listed, left alone, and Home Assistant raises a repair notification
asking you to decide.

---

By Matthias Kerstner ([@mkerstner](https://github.com/mkerstner))
