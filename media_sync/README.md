# Media Sync

Keeps your media library and a remote server in sync, in both directions, and
asks before it deletes anything.

Works with any server you can reach over SSH — a NAS, a VPS, a rented storage
box. Pairs with the [Media Sync integration](https://github.com/mkerstner/media-sync-integration),
which adds buttons, status and the deletion confirmation to Home Assistant.

Start a sync from a dashboard button, from an automation, or by running the
script yourself in a terminal — the result shows up in Home Assistant either
way.

Everything travels over an encrypted SSH connection. The app logs in with a key
pair it creates itself, so there is no password to store, and the private key
never leaves your machine.

See [DOCS.md](DOCS.md) for setup and settings.
