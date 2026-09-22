# Page Turner for KOReader

Minimal Kindle plugin and phone PWA: scan a pairing QR and send authenticated HTTP commands to turn the open book **next** or **back**. Designed against KOReader **2026.03** source. QR pairing and camera scanning are implemented but still require on-device validation.

No voice input yet. No changes to KOReader settings, sleep timers, Wi-Fi management, touch controls, or page-rendering behavior. The server is manually enabled per open book.

## Install

1. On your laptop, from this directory (Python 3.9+):

   ```sh
   python3 tools/pageturner.py configure
   ```

   This creates `pageturner.koplugin/config.lua` containing only the listener port. It refuses to overwrite existing configuration. Default port: **8088**; use `configure --port 8089` if needed. The Kindle generates the bearer token securely in memory on each manual listener start.

2. Copy the **entire `pageturner.koplugin` folder**, including the generated `config.lua`, into the Kindle's KOReader `plugins` folder:

   ```text
   koreader/plugins/pageturner.koplugin/main.lua
   koreader/plugins/pageturner.koplugin/config.lua
   koreader/plugins/pageturner.koplugin/...
   ```

   On typical Kindle installations this is `/mnt/us/koreader/plugins/` (the `koreader/plugins` directory on the USB drive). Use your actual KOReader installation location. No extra Kindle dependencies are needed beyond KOReader's bundled LuaSocket.

3. Safely eject the Kindle, restart KOReader, and open a book. Tap the top of the screen → **Tools → Page Turner (HTTP) → Start Page Turner**. Page Turner is the first entry on the default Tools menu, not inside More tools. Explicit custom menu-order settings still take precedence. If it is missing, check KOReader's plugin manager and restart after enabling it.
4. Starting the listener creates a new session token and checks private Tailscale Serve with a bounded background command. It uses private Serve only when the active mapping proxies to this plugin's port; otherwise it falls back to the current local Wi-Fi IPv4 address.
5. A pairing QR appears with **Private Tailscale** or **Local Wi-Fi** and the selected endpoint printed below it. In the Page Turner PWA, choose **Scan Kindle pairing QR** and grant camera permission. Scanning configures the endpoint/token but sends no page-turn request.
6. Tap the Kindle QR to dismiss it, close the KOReader menu so the book is visible, and then send one coordinated command. Use **Show pairing QR** to reopen it and **Connection details (route / IP / port)** for token-free diagnostics. Unsupported/missing details display “Unavailable”; the plugin never enables or reconfigures Wi-Fi.

## Update an installed copy

Stop Page Turner and exit KOReader before copying the complete updated `pageturner.koplugin` folder. Keep the existing `config.lua`; any legacy `token` field is ignored and may remain. Ensure these new pairing files are present:

- `pageturner_pairing.lua`
- `pageturner_endpoint.lua`
- `pageturner_pairing_message.lua`

Safely eject, restart KOReader, open a book, and confirm that Start displays a scannable QR and the correct private/local route. Do not replace the separate Tailscale extension's registered `state/` directory.

## Send commands

The normal client is the PWA. Its scanner reads this versioned QR payload entirely on-device:

```json
{"version":1,"endpoint":"https://kindle.example.ts.net","token":"<session-token>"}
```

The token is not shown below the QR, persisted by the PWA, put in the endpoint URL, or logged. The PWA sends one bodyless authenticated POST only after the user taps Next or Back.

`tools/pageturner.py` remains a low-level diagnostic client, but its old `.pageturner-token` no longer automatically matches because every manual Start rotates the Kindle session token. If a current token is deliberately supplied in a private token file, the existing `--token-file` option can be used. Never place the token directly in shell arguments, URLs, screenshots, or logs.

### HTTP contract

- `POST /next` / `POST /back`, with `Authorization: Bearer <token>` and an empty body.
- Browser access is allowed only from the exact origin `https://iamads.github.io`. A valid bodyless `OPTIONS` preflight for POST plus Authorization on `/next` or `/back` receives `204`; it never requires the token or turns a page. Actual POSTs remain authenticated.
- `202`: authenticated command accepted for dispatch on KOReader's next UI tick. **Not confirmation of a visible page change.** The body includes a per-book request counter for matching Kindle logs.
- `401`: missing/incorrect token on an actual command; no turn.
- `409`: book not in the foreground, a menu/dialog is open, or a turn is already pending; no turn.
- `400` / `404` / `405`: invalid request, unsupported path, or unsupported method; no turn.
- `431`: request headers exceed 4 KiB. At most four clients are serviced at once; incomplete requests expire after two seconds.
- Connections close after one response. No command batching, arbitrary event execution, request bodies, retries, or deduplication protocol.

**Do not blindly retry a timed-out request:** the Kindle might already have accepted it. Check the screen first. Similarly, do not assume acceptance guarantees movement at the beginning/end of a book. Normal reader boundary behavior is preserved. A queued command is cancelled if the reader is covered/closed or the listener stops before dispatch.

## Lifecycle and safety

- Choose **Stop Page Turner** to stop listening and invalidate the session token. Closing the book or exiting KOReader does the same; a new manual Start generates a new token.
- Normal suspend/standby temporarily stops the listener. Normal resume restores it only if enabled for that book and retains the same session token, so an interrupted reading session does not require rescanning. There is no remote wake, Wi-Fi activation, wake lock, sleep-setting write, or synthetic `InputEvent` to keep it awake. It may become unreachable when the Kindle normally sleeps or disables Wi-Fi.
- The reader's existing `GotoViewRel(+1/-1)` handles navigation, including its current reading mode. Scroll mode uses its normal view-relative movement, not a forced switch to paged mode.
- Menus/dialogs are never dismissed remotely. Close them locally before sending commands.
- While enabled, the listener polls through KOReader's existing UI-manager mechanism. This and active Wi-Fi may increase power usage; no battery claim has been validated.
- On Kindle, startup adds a private `KR_PAGETURNER` iptables chain and narrowly scoped TCP rules for the configured port. Stop/suspend/exit removes its own rules only. No global firewall policy is changed. If setup fails, startup rolls back.
- A force-kill/crash can leave firewall rules behind. Restarting the Kindle should clear nonpersistent rules; if it does not, inspect `iptables -S` via your existing shell access. Do not flush the device firewall. The plugin refuses to take over an existing chain it did not create.
- A local-IP pairing is for **trusted local Wi-Fi only**: plain HTTP does not encrypt the token. Private Tailscale Serve encrypts the phone-to-Kindle path and remains tailnet-only. Never enable Funnel or port-forward the listener.
- Anyone who can photograph/scan the displayed QR can control the active listener until its token is invalidated. Dismiss the QR after pairing; tokens remain in memory and are omitted from logs and visible endpoint text.

To uninstall, stop the listener, exit KOReader, then remove `pageturner.koplugin`. No reader settings need restoring.

## Verify on your Kindle

1. Record Kindle model, firmware, KOReader version, and a book/reading mode. Start away from the book's first/last page.
2. Send **20 alternating next/back commands**, one at a time. Check that each produces exactly one correct visible turn. Record HTTP/timing output and any discrepancy; HTTP success alone is not a pass.
3. Verify normal touch navigation, menus, book close/reopen, saved reading position, and ordinary suspend/resume still work. Check that stopped/disabled Page Turner no longer listens.
4. Confirm a wrong/missing token cannot turn a page. Restart KOReader and confirm the plugin loads but is not listening until manually started.
5. After the first demonstration, try **two 30-minute reading sessions** with no missed/duplicate turns or disruption to normal behavior. Record any sleep/network interruptions rather than changing power settings to conceal them.

The <100 ms delivery target is an aspiration, not a v1 blocker. Client timing includes TCP setup and the full acknowledgement round trip, not e-ink refresh. KOReader's `crash.log` normally contains `PageTurner: accepted` / `dispatched` / `cancelled` records. Server timing (`accept_to_handler_return_ms`) includes scheduling and navigation-handler work; it is not network RTT or confirmed display latency.

## Troubleshooting

- **Timeout/refused connection:** verify the IP/port, Wi-Fi, awake state, server menu status, and router client isolation. Check `crash.log` for bind/firewall errors. The plugin cannot prevent normal sleep or bypass Wi-Fi isolation.
- **401:** scan the QR generated by the current manual Start. A QR/token from an earlier stopped or closed session is intentionally invalid.
- **409:** close menus/dialogs and wait for the previous command to finish.
- **Port already in use:** change only this plugin's `config.lua` port and pass the same port to the client; stop/start the plugin afterward.
- **Accepted but no turn:** inspect the screen, book boundaries, reading mode, and `PageTurner` logs. A document switch or dialog appearing before dispatch cancels the queued command intentionally.

## Test browser connectivity and scoped CORS

Page Turner has token-safe transport logs and narrowly scoped CORS for the GitHub Pages PWA. It accepts browser preflight only for the exact origin `https://iamads.github.io`, routes `/next` and `/back`, method POST, and header Authorization. Actual page-turn POSTs still require the current session token and all reader guards. Scanning a QR configures the PWA only; it does not trigger preflight or a command.

1. Stop Page Turner and exit KOReader. Copy the complete updated
   `pageturner.koplugin/` folder into the existing KOReader plugins directory,
   preserving the installed `config.lua`. This includes the HTTP/CORS and new
   pairing modules.
2. Keep the existing `config.lua`. Restart KOReader, open a book, start Page
   Turner, scan the new pairing QR, then close the QR and menus.
3. In Chrome, open DevTools **Console** and **Network** (all requests, including
   OPTIONS). Open the Pages PWA, scan the QR (or use manual fallback), and tap
   Next **once**. Observe the Kindle before any further command.
4. Inspect the corresponding `PageTurner:` lines in `koreader/crash.log` using
   existing shell/file access. Do not attach the entire log or an unredacted HAR;
   browser request headers contain the bearer token.

A successful browser interaction should first log an unauthenticated preflight,
then a separately authenticated POST (logger timestamp/format may differ):

```text
PageTurner: transport connection=1 connected
PageTurner: transport connection=1 request method=OPTIONS route=/next origin=pages auth=absent requested_method=POST requested_headers=authorization private_network=absent
PageTurner: transport connection=1 response_status 204
PageTurner: transport connection=1 closed response_sent
PageTurner: transport connection=2 connected
PageTurner: transport connection=2 request method=POST route=/next origin=pages auth=present requested_method=absent requested_headers=absent private_network=absent
PageTurner: transport connection=2 response_status 202
PageTurner: transport connection=2 closed response_sent
```

Interpretation:

- **OPTIONS + 204:** The approved preflight passed. Missing auth on OPTIONS is
  normal; preflight only grants permission to attempt the authenticated POST.
- **OPTIONS + 400/403/404/405:** Origin, route, requested method/header, body, or
  private-network request was outside the narrow allowlist. No turn occurred.
- **POST + 401:** The command reached the plugin but authentication failed.
- **POST + 202:** Accepted for deferred dispatch; check existing `accepted`,
  `dispatched`, and `cancelled` lines and the visible Kindle page. A browser can
  still report a CORS error after the server accepted a command. Do not retry.
- **409:** Reader covered/not available or another turn pending.
- **Connected, then timeout/read error:** A TCP connection arrived but no complete
  valid exchange finished. Browser speculative connections may also do this.
- **No transport lines:** Not conclusive alone. First confirm the updated listener
  and logging using the harmless OPTIONS control below. Then inspect browser
  mixed-content, local-network permission, OS permission, and network errors.

Optional non-mutating control from the laptop (no token and no page turn).
Replace the example address with the Kindle's current IP:

```sh
curl --max-time 3 -i -X OPTIONS \
  -H 'Origin: https://iamads.github.io' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: authorization' \
  http://192.168.0.102:8088/next
```

The expected response is **204** with the fixed `Access-Control-Allow-Origin`,
`-Methods`, and `-Headers` values. This control validates reachability and the
preflight response, but not the browser's local-network permission, authenticated
POST, visible page movement, or iPhone support.

Diagnostics use connection IDs (reset on listener restart), fixed method/route
labels, `origin=pages/other/absent`, auth **presence only**, classified preflight
fields, HTTP status, and close reasons. Raw headers, URL query strings, arbitrary
origins, socket/handler error text, and tokens are never logged. Logging occurs
only at connection/request/response/close transitions, not every UI poll.

CORS is not authentication and does not encrypt the LAN token. Wildcard/arbitrary
origins, methods, headers, and endpoints remain rejected. Chrome has now reported
the missing allowed-origin header specifically; this implementation addresses
that obstacle. Actual iPhone behavior remains untested. See
[hosting strategies](docs/mobile-pwa-hosting-strategies.md).

## Development tests

```sh
luajit tests/test_plugin.lua
luajit tests/test_network.lua
python3 -m unittest discover -s tests -p 'test_*.py' -v
node --test tests/test_pwa_endpoint.mjs
```

Lua tests use KOReader/socket doubles. Python tests exercise the laptop client with a real local HTTP fixture. Optional real LuaSocket transport tests (LuaSocket must be available to LuaJIT):

```sh
PAGETURNER_SOCKET_TESTS=1 python3 -m unittest discover -s tests -p 'test_*.py' -v
```

These do **not** validate Kindle firewall behavior, QR rendering/readability, phone camera permission/decoding, actual browser transport, or device power behavior. Source research and design limits: [`docs/koreader-research.md`](docs/koreader-research.md). Product sequencing: [`roadmap.md`](roadmap.md).
