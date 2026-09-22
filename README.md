# Page Turner for KOReader

Turn KOReader pages from a phone. A Kindle plugin runs a small authenticated HTTP server; a phone camera opens the pairing link in the hosted web app, which provides large **Next** and **Back** controls.

**Web app:** https://iamads.github.io/pageturner/

The current native-camera pairing flow is deployed and owner-confirmed working on the tested Kindle/iPhone setup. The reference setup is a Kindle Paperwhite 3 running KOReader 2026.03, private Tailscale Serve, and an iPhone connected to the same tailnet. Other Kindle/KOReader versions and Android's direct-LAN path have not been validated.

No voice input yet. Page Turner does not modify KOReader navigation, Kindle sleep settings, Wi-Fi settings, or touch controls. The listener must be started manually for each open book.

## How it works

1. In KOReader, **Start Page Turner** creates a fresh random session token and starts the listener.
2. The plugin chooses an endpoint:
   - the active private Tailscale Serve URL when it proxies to the configured Page Turner port; or
   - the Kindle's current local Wi-Fi address as a fallback.
3. The Kindle displays a QR containing a normal link to the hosted app. The endpoint and token are encoded after `#` in the URL fragment.
4. Scan the QR with the phone's normal camera and open the link. The fragment is not sent to GitHub Pages. The app extracts it, removes it from the address bar/history entry, and keeps the credentials only in memory.
5. The app sends an authenticated, non-mutating `POST /connect`. **Connected** enables the controls; failure is shown inline and can be retried without turning a page.
6. Dismiss the Kindle QR and KOReader menus. Each **Next** or **Back** tap sends exactly one authenticated command.

The hosted app is static: it does not relay commands or store credentials. The phone connects directly to the selected Kindle endpoint. Reloading the page clears the in-memory connection, so scan again or use **Enter connection manually**.

## Requirements

- A Kindle capable of running KOReader and installing custom KOReader plugins.
- KOReader; this project was developed against **2026.03**.
- A computer and USB connection for installation.
- A phone with a QR-capable camera.
- For the tested iPhone path: a Tailscale account, Tailscale on the phone, KUAL on the Kindle, and the included private-Tailscale extension. Direct HTTP from the HTTPS app was blocked by the tested iPhone browser.
- For Android/direct local Wi-Fi: the plugin supports it, but browser compatibility is not yet validated. Use only on trusted Wi-Fi because this path is unencrypted.

## Install for yourself

### 1. Prepare the KOReader plugin

Clone/download this repository, then from its root run:

```sh
python3 tools/pageturner.py configure
```

This creates `pageturner.koplugin/config.lua` with the default listener port, `8088`. To choose another port:

```sh
python3 tools/pageturner.py configure --port 8089
```

The port is the only persistent plugin configuration. A bearer token is generated securely in memory each time Page Turner is manually started.

Copy the complete `pageturner.koplugin/` directory to the Kindle so the result is typically:

```text
/mnt/us/koreader/plugins/pageturner.koplugin/main.lua
/mnt/us/koreader/plugins/pageturner.koplugin/config.lua
```

Safely eject the Kindle and restart KOReader. Open a book and verify that **Tools → Page Turner (HTTP)** appears.

### 2. Choose the network path

#### Recommended/tested on iPhone: private Tailscale Serve

The phone and Kindle must join the same private tailnet. The Kindle extension runs Tailscale in userspace mode and privately serves HTTPS to Page Turner's local port; it never enables Funnel.

Follow [`kindle-kual/README.md`](kindle-kual/README.md) to:

1. download and verify the tested ARM Tailscale binaries;
2. install `kindle-kual/pageturner-tunnel/` under `/mnt/us/extensions/`;
3. install Tailscale on the phone and sign in to the same account;
4. register the Kindle with a one-use auth key; and
5. configure **private HTTPS Serve** for port `8088`.

Keep Tailscale connected on the phone while using Page Turner. Never enable Funnel or expose the listener publicly.

#### Optional: direct local Wi-Fi

If private Serve is not active, the plugin creates a QR for `http://<kindle-ip>:<port>`. This may work from browsers that permit an HTTPS page to access a private HTTP endpoint. It did not work in the tested iPhone WebKit environment and has not yet been validated on Android.

Use direct HTTP only on trusted Wi-Fi: anyone able to observe the traffic may obtain the session token.

### 3. Pair and use

1. On the phone, optionally open the deployed app once to ensure the latest shell is available: **https://iamads.github.io/pageturner/**.
2. Ensure private Tailscale is running on both devices if using the tested iPhone path.
3. Open a book in KOReader.
4. Select **Tools → Page Turner (HTTP) → Start Page Turner**.
5. Confirm the Kindle QR says **Private Tailscale** or **Local Wi-Fi** and displays the expected endpoint.
6. Scan the QR with the phone's normal camera and open the Page Turner link.
7. Wait for the inline **Connected** message. Pairing does not turn a page.
8. Tap the Kindle QR to close it and close KOReader menus so the book is visible.
9. Use **Next** and **Back**. Optionally start the web app's foreground wake lock.
10. Select **Stop Page Turner** when finished.

A native camera may open the browser rather than an installed Home Screen PWA; that handoff is controlled by the phone OS. The controls work in the opened web page. If you need a separate installed-app context, use the manual connection modal there.

## Updating

1. Stop Page Turner and exit KOReader.
2. Preserve the Kindle's existing `pageturner.koplugin/config.lua`.
3. Replace the rest of `/mnt/us/koreader/plugins/pageturner.koplugin/` with the current repository version.
4. Do **not** overwrite `/mnt/us/extensions/pageturner-tunnel/state/`; it contains the Kindle's private Tailscale identity and certificate state.
5. Safely eject and restart KOReader.

The hosted app updates independently through GitHub Pages and its service worker. If an old interface remains, fully close the page/app, reopen https://iamads.github.io/pageturner/, and reload.

## Security and lifecycle

- The pairing QR is a credential. Anyone who captures it can control the current listener session. Dismiss it after pairing and never share or screenshot it.
- Credentials are placed only in the URL fragment, not the query string. GitHub Pages does not receive fragments. The camera/browser can still see the original link.
- The app removes the fragment immediately and does not persist or log the token.
- Each manual Start creates a new token. Stop, book close, or KOReader exit invalidates it.
- Normal suspend/resume retains the token for that reading session, but the Kindle may be unreachable while asleep or Wi-Fi is unavailable.
- Private Tailscale Serve is tailnet-only and encrypted. Funnel/public exposure and router port-forwarding are unsupported.
- A page-turn timeout is uncertain: the Kindle may already have accepted the command. Check the screen; the app never retries a turn automatically.
- Menus/dialogs are not dismissed remotely. A turn returns `409` unless the book is foregrounded and no other turn is pending.

## Troubleshooting

- **Connection failed:** confirm Page Turner is running, the Kindle is awake, and the phone is connected to the expected Wi-Fi/Tailscale network. Then use **Retry connection**.
- **Private Tailscale QR not selected:** in KUAL, start private Tailscale and check **Show private Serve status**. Serve must map to the same port as `config.lua`.
- **401 / authentication rejected:** stop/start Page Turner and scan the newly generated QR; old session tokens are intentionally invalid.
- **409:** close the Kindle QR and all KOReader menus/dialogs, then wait for any pending turn.
- **Accepted but no visible turn:** check book boundaries and KOReader's `crash.log` for `PageTurner: accepted`, `dispatched`, or `cancelled`.
- **Port already in use:** change `config.lua` to another port. Private Serve currently targets `8088`; update its backend script/configuration too if changing the port.
- **Old web interface:** fully close and reopen the hosted app, then reload so the current service worker activates.

Use **Show pairing QR** to reopen the current session's QR and **Connection details (route / IP / port)** for token-free diagnostics.

## HTTP API

All actual requests are bodyless and require:

```text
Authorization: Bearer <current-session-token>
```

- `POST /connect` → `204` when authenticated; never turns a page.
- `POST /next` or `POST /back` → `202` when accepted for dispatch.
- `401` → missing or invalid token.
- `409` → book not foregrounded/menu open, or another turn is pending.
- `400`, `404`, `405`, `431` → invalid request, route, method, or oversized headers.

Browser CORS is restricted to the exact hosted-app origin, `https://iamads.github.io`, and only `/connect`, `/next`, `/back`, `POST`, and `Authorization`. Self-hosting the web app requires deliberately changing `ALLOWED_ORIGIN` in `pageturner.koplugin/pageturner_http.lua` and the project URL in `pageturner_pairing.lua`.

## Uninstall

1. Stop Page Turner and exit KOReader.
2. Remove `/mnt/us/koreader/plugins/pageturner.koplugin/`.
3. If also removing Tailscale, first disable private Serve and stop private Tailscale through KUAL. See [`kindle-kual/README.md`](kindle-kual/README.md) for account/state cleanup.

## Development

Run the local test suite from the repository root:

```sh
luajit tests/test_plugin.lua
luajit tests/test_network.lua
python3 -m unittest discover -s tests -p 'test_*.py' -v
node --test tests/test_pwa_*.mjs
```

Optional real-LuaSocket tests require LuaSocket:

```sh
PAGETURNER_SOCKET_TESTS=1 python3 -m unittest discover -s tests -p 'test_*.py' -v
```

The normal client is the hosted web app. `tools/pageturner.py` remains a low-level diagnostic command client when a current token is deliberately supplied through a private token file.

Architecture and device history are recorded in [`docs/mobile-pwa-handoff.md`](docs/mobile-pwa-handoff.md). Product sequencing remains in [`roadmap.md`](roadmap.md).
