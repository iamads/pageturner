# Private Tailscale for Page Turner

This KUAL extension gives Page Turner a private HTTPS address that an iPhone can reach from the hosted web app. It runs an isolated Tailscale daemon in userspace mode, registers the Kindle in your tailnet, and configures **Tailscale Serve** to proxy:

```text
https://pageturner-kindle.<your-tailnet>.ts.net
    → http://127.0.0.1:8088
```

It does **not** enable Funnel, Tailscale SSH, exit nodes, subnet routes, or public access.

The tested device is a Kindle Paperwhite 3 with firmware 5.12.3, KUAL, and KOReader 2026.03. Tailscale does not officially target this old Kindle platform; test other devices carefully.

## Requirements

- KUAL and KOReader installed on the Kindle.
- A Tailscale account.
- The official Tailscale app installed and signed in on the phone.
- A computer/USB connection.
- Approximately 70 MB for the two ARM binaries plus state/logs.

## 1. Prepare the extension

The large Tailscale binaries are intentionally not stored in Git. Download the tested official archive:

```text
https://pkgs.tailscale.com/stable/tailscale_1.102.4_arm.tgz
```

Expected archive SHA-256:

```text
b981a59cb85fb923ee6e1860ee6934772c83a840a6627f0dbfd7711ed690b869
```

Verify it before extracting. For example, on macOS:

```sh
shasum -a 256 tailscale_1.102.4_arm.tgz
```

On Linux:

```sh
sha256sum tailscale_1.102.4_arm.tgz
```

Extract it and copy the `tailscale` and `tailscaled` ARM executables into:

```text
kindle-kual/pageturner-tunnel/bin/tailscale
kindle-kual/pageturner-tunnel/bin/tailscaled
```

The individual expected hashes and source details are in [`pageturner-tunnel/bin/PROVENANCE.txt`](pageturner-tunnel/bin/PROVENANCE.txt).

Copy the complete prepared `pageturner-tunnel/` folder to the Kindle:

```text
/mnt/us/extensions/pageturner-tunnel/menu.json
/mnt/us/extensions/pageturner-tunnel/bin/tailscale
/mnt/us/extensions/pageturner-tunnel/bin/tailscaled
```

Safely eject the Kindle and open KUAL. **Page Turner Tunnel** should appear.

## 2. Optional compatibility checks

Before registration, these KUAL actions are safe diagnostics:

1. **Check compatibility** — records basic kernel/CPU/memory/storage/TUN/CA information in `/mnt/us/pageturner-compatibility.txt`.
2. **Test current Tailscale launch** — runs only `tailscale version` and `tailscaled --version`.
3. **Test temporary Tailscale daemon** — runs a logged-out, in-memory userspace daemon for about 15 seconds, checks its local API/resource use, and cleans it up.

These checks do not register the Kindle or configure Serve/Funnel.

## 3. Register the Kindle once

Create a one-use key in the [Tailscale admin console](https://login.tailscale.com/admin/settings/keys):

- **Reusable:** off
- **Ephemeral:** off
- **Pre-approved:** on, if available
- **Expiration:** one day
- **Tags:** none, unless your own tailnet policy requires an approved tag

Save the key as a plain-text file named `auth.key`, containing only the key on one line. Copy it to:

```text
/mnt/us/extensions/pageturner-tunnel/private/auth.key
```

Never commit, screenshot, share, or put the key in a URL.

Safely eject and select:

```text
KUAL → Page Turner Tunnel → Register Kindle with auth key
```

This starts the private userspace daemon, registers the machine as `pageturner-kindle`, and deletes `private/auth.key` after successful registration. Registration state remains in:

```text
/mnt/us/extensions/pageturner-tunnel/state/
```

Confirm success with **Show private Tailscale status** and in the Tailscale Machines admin page.

Install/sign in to Tailscale on the phone using the same tailnet. Keep it connected while using Page Turner.

## 4. Configure private HTTPS Serve

The bundled script targets Page Turner's default port, `8088`.

1. Open a book in KOReader and start Page Turner once.
2. Open KUAL → **Page Turner Tunnel → Configure private HTTPS Serve**.
3. The action starts/reuses the daemon and waits for the tailnet connection.
4. On first setup, Tailscale may display an HTTPS-approval URL on the Kindle. Open that URL while signed into the Tailscale admin account and approve HTTPS.
5. Select **Show private Serve status** and verify that it displays a private `https://…ts.net` endpoint proxying to `http://127.0.0.1:8088`.

Serve configuration persists. The daemon uses the explicit writable `state/` directory for both node identity and managed certificate material; do not delete or overwrite it during normal updates.

If Page Turner uses a custom port, edit `BACKEND` in `scripts/configure-private-serve.sh` and keep it consistent with `pageturner.koplugin/config.lua`.

## Normal use

After one-time registration/configuration:

1. Connect the phone's Tailscale app.
2. In KUAL, select **Start private Tailscale**. Running **Configure private HTTPS Serve** also starts it when needed.
3. Optionally confirm **Show private Serve status**.
4. Open a book in KOReader and select **Start Page Turner**.
5. The pairing QR should say **Private Tailscale**.
6. Scan it with the phone's native camera and open https://iamads.github.io/pageturner/.

To stop the tunnel without losing registration, select **Stop private Tailscale**. To remove only the HTTPS proxy configuration, select **Disable private Serve**.

## Updating safely

Do not replace the complete installed extension after registration. Preserve these Kindle directories:

```text
/mnt/us/extensions/pageturner-tunnel/state/
/mnt/us/extensions/pageturner-tunnel/private/
```

`state/` contains the machine identity and certificate material. Copy updated scripts, `menu.json`, `config.xml`, or binaries individually. Stop private Tailscale before replacing binaries.

Repository `state/`, `private/`, and `logs/` contain only placeholders; copying them over the installed extension can destroy working state.

## Logs and troubleshooting

Logs are written under:

```text
/mnt/us/extensions/pageturner-tunnel/logs/
```

Useful KUAL actions:

- **Show private Tailscale status** — confirms tailnet connectivity.
- **Show private Serve status** — confirms the HTTPS URL and local proxy target.
- **Start private Tailscale** — reconnects using existing state; no auth key is needed.
- **Configure private HTTPS Serve** — resets/recreates private Serve and may request HTTPS approval.

Common failures:

- **Missing tailscaled binary:** prepare/copy both official ARM executables into `bin/`.
- **Missing KOReader CA bundle:** this setup requires `/mnt/us/koreader/data/ca-bundle.crt`.
- **Tailscale process exists but socket is missing:** restart the Kindle, then try again.
- **Tailnet connection timeout:** check the Kindle network and machine status in Tailscale admin.
- **Serve active but TLS fails / `no TailscaleVarRoot`:** ensure the current `start-private-tailscale.sh` launches with `--statedir=<extension>/state`; stop and restart the daemon once after updating that script.
- **QR shows Local Wi-Fi:** Serve is inactive, unreachable, or not mapped to Page Turner's configured port. Run **Show private Serve status**.

Review logs before sharing them. Never share auth keys, `tailscaled.state`, certificate keys, pairing links, or Page Turner bearer tokens.

## Complete removal

1. Select **Disable private Serve**.
2. Select **Stop private Tailscale**.
3. Remove `pageturner-kindle` from the Tailscale Machines admin page.
4. Delete `/mnt/us/extensions/pageturner-tunnel/` from the Kindle.
5. Delete the optional compatibility reports from `/mnt/us/` if present.

Deleting the extension's `state/` is destructive: registration cannot be recovered without registering again.
