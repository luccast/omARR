# Security

omARR runs inside the long-lived `omarchy-shell` process, unsandboxed, with your user permissions. Treat every URL and credential as if the plugin can reach anything your account can.

## What it talks to

- Only the HTTP(S) URLs you add (plus `http://127.0.0.1:<port>` during a local scan).
- Desktop notifications via `omarchy-notification-send`.
- The default browser via `omarchy launch browser <url>`.

No telemetry. No third-party hosts. No Node, Python, or extra runtime. Dashboard Icons are bundled under `icons/` and never fetched from a CDN.

## Credentials

API keys, Plex tokens, Jellyfin API keys, qBittorrent passwords, and cookie jars never go in `shell.json` or process argv.

- Secrets live in `~/.local/state/omarchy/omarr/credentials.json`, directory mode `0700`, file mode `0600`.
- State and cache dirs are created as real `0700` directories owned by the user. A symlink at that path is refused.
- Secret files (credentials, seen ids, curl header/body) are written to an exclusive `mktemp` file in that directory, `chmod 600`, then `mv` onto the destination so a leftover symlink is replaced instead of followed.
- `X-Api-Key` is written to that `0600` header file and passed to curl as `-H @file`.
- Plex `X-Plex-Token` (plus `Accept`) is written as a `0600` curl config and passed as `--config file`, never argv.
- Jellyfin `Authorization` (plus `Accept`) is written as a `0600` curl config and passed as `--config file`, never argv.
- SABnzbd and qBittorrent form bodies are written to a `0600` file and passed as `--data-binary @file`.
- Poster/art downloads and qBittorrent cookie jars use the same temp-file + `mv` install into `~/.cache/omarchy/omarr/` (`0700`). curl `-o`/`-c` never point at the final path.

## HTTP

Every request is `curl --proto =http,https` with `--max-time` and `--max-filesize`. URLs that are not `http://` or `https://` are refused. Redirect following is off. Reply strings render as `PlainText` and elide, so a hostile name cannot shove the layout.

## Notifications

Toasts are sent with `omarchy-notification-send`, never raw `notify-send`. The first successful poll seeds seen event ids so enabling the plugin does not dump history as toasts.
