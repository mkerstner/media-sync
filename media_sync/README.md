# Media Sync

Keeps your media library and a remote server in sync, in both directions, and
asks before it deletes anything — deletion protection is on by default and can
be turned off whenever you like.

## Two ways to connect

**SSH** — any server you can reach over SSH: a NAS, a VPS, a rented storage
box. The app logs in with a key pair it creates for itself, so there is no
password to store and the private key never leaves your machine.

**WebDAV** — Nextcloud, and anything else that speaks it. Give it the address
of your Nextcloud and an app password, and it works out the rest.

Choose under **How to connect**. Both do the same job: both directions, newest
wins, include and exclude rules, test runs, and the folder-by-folder review
before anything is deleted.

### Before choosing WebDAV

Check whether the Nextcloud folder is **external storage** rather than storage
of Nextcloud's own. If it is, it is a view onto something else — often reached
over SFTP — and syncing it over WebDAV puts Nextcloud in the middle of a path
you can take directly. It is slower, and the extra layer brings failures of its
own. Point the app at that storage instead, which for SFTP is the SSH option.

WebDAV is the right choice when the files really are Nextcloud's own.

## Running it

Start a sync from a dashboard button, from an automation, or by running the
script yourself in a terminal — the result shows up in Home Assistant either
way.

Pairs with the [Media Sync integration](https://github.com/mkerstner/media-sync-integration),
which adds buttons, status and the deletion confirmation to Home Assistant.

Everything travels encrypted whichever you pick: SSH, or HTTPS for WebDAV.

Setup and settings are on the **Documentation** tab.
