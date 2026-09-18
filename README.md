# Page Turner for KOReader

Minimal Kindle plugin: send authenticated HTTP commands from your laptop to turn the open book **next** or **back**. Designed against KOReader **2026.03** source; **not yet tested on a physical Kindle**.

No voice input yet. No changes to KOReader settings, sleep timers, Wi-Fi management, touch controls, or page-rendering behavior. The server is manually enabled per open book.

## Install

1. On your laptop, from this directory (Python 3.9+):

   ```sh
   python3 tools/pageturner.py configure
   ```

   This generates a random shared token in `.pageturner-token` and `pageturner.koplugin/config.lua`. Keep both private. It refuses to overwrite existing configuration. Default port: **8088**; use `configure --port 8089` if needed.

2. Copy the **entire `pageturner.koplugin` folder**, including the generated `config.lua`, into the Kindle's KOReader `plugins` folder:

   ```text
   koreader/plugins/pageturner.koplugin/main.lua
   koreader/plugins/pageturner.koplugin/config.lua
   koreader/plugins/pageturner.koplugin/...
   ```

   On typical Kindle installations this is `/mnt/us/koreader/plugins/` (the `koreader/plugins` directory on the USB drive). Use your actual KOReader installation location. No extra Kindle dependencies are needed beyond KOReader's bundled LuaSocket.

3. Safely eject the Kindle, restart KOReader, and open a book. Find **Page Turner (HTTP)** under the main menu's tools/more-tools section and choose **Start Page Turner**. If it is missing, check KOReader's plugin manager and restart after enabling it.
4. Close the menu so the book itself is visible. Put both devices on the same trusted Wi-Fi and find the Kindle's Wi-Fi IPv4 address in its network information or your router's client list. Enable Wi-Fi yourself if necessary; the plugin will not do it.

## Send commands

Replace `192.168.1.42` with your Kindle's address:

```sh
python3 tools/pageturner.py next --host 192.168.1.42 --log timing.jsonl
python3 tools/pageturner.py back --host 192.168.1.42 --log timing.jsonl
```

The client reads `.pageturner-token` automatically. If you changed the port, add `--port 8089`. Each command prints a JSON record including HTTP status, acceptance message, and `round_trip_ms`. `--log` additionally appends the same record to a file. Tokens are not logged.

Direct HTTP requests also work:

```sh
# Load the header via stdin so the token is not passed in curl's argument list.
printf 'Authorization: Bearer %s\n' "$(< .pageturner-token)" |
  curl --max-time 3 --header @- --request POST --data '' \
    --write-out '\nround_trip_seconds=%{time_total}\n' \
    http://192.168.1.42:8088/next
```

Use `/back` for the opposite direction. The shell example above is for bash/zsh.

### HTTP contract

- `POST /next` / `POST /back`, with `Authorization: Bearer <token>` and an empty body.
- `202`: authenticated command accepted for dispatch on KOReader's next UI tick. **Not confirmation of a visible page change.** The body includes a per-book request counter for matching Kindle logs.
- `401`: missing/incorrect token; no turn.
- `409`: book not in the foreground, a menu/dialog is open, or a turn is already pending; no turn.
- `400` / `404` / `405`: invalid request, unsupported path, or unsupported method; no turn.
- `431`: request headers exceed 4 KiB. At most four clients are serviced at once; incomplete requests expire after two seconds.
- Connections close after one response. No command batching, arbitrary event execution, request bodies, retries, or deduplication protocol.

**Do not blindly retry a timed-out request:** the Kindle might already have accepted it. Check the screen first. Similarly, do not assume acceptance guarantees movement at the beginning/end of a book. Normal reader boundary behavior is preserved. A queued command is cancelled if the reader is covered/closed or the listener stops before dispatch.

## Lifecycle and safety

- Choose **Stop Page Turner** to stop listening. Closing the book or exiting KOReader stops it; start it again after reopening/changing books or restarting KOReader.
- Normal suspend/standby stops the listener. Normal resume restores it only if you had enabled it for that book. There is no remote wake, Wi-Fi activation, wake lock, sleep-setting write, or synthetic `InputEvent` to keep it awake. It may become unreachable when the Kindle normally sleeps or disables Wi-Fi.
- The reader's existing `GotoViewRel(+1/-1)` handles navigation, including its current reading mode. Scroll mode uses its normal view-relative movement, not a forced switch to paged mode.
- Menus/dialogs are never dismissed remotely. Close them locally before sending commands.
- While enabled, the listener polls through KOReader's existing UI-manager mechanism. This and active Wi-Fi may increase power usage; no battery claim has been validated.
- On Kindle, startup adds a private `KR_PAGETURNER` iptables chain and narrowly scoped TCP rules for the configured port. Stop/suspend/exit removes its own rules only. No global firewall policy is changed. If setup fails, startup rolls back.
- A force-kill/crash can leave firewall rules behind. Restarting the Kindle should clear nonpersistent rules; if it does not, inspect `iptables -S` via your existing shell access. Do not flush the device firewall. The plugin refuses to take over an existing chain it did not create.
- **Trusted local Wi-Fi only.** The bearer token prevents unauthenticated commands but plain HTTP does not encrypt traffic or the token. Do not port-forward this server, expose it publicly, or use it on hostile/shared networks. Configuration files on the Kindle's USB storage may not support private file permissions.

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
- **401:** the local `.pageturner-token` must match `config.lua` on the Kindle. Copying only `main.lua` is insufficient.
- **409:** close menus/dialogs and wait for the previous command to finish.
- **Port already in use:** change only this plugin's `config.lua` port and pass the same port to the client; stop/start the plugin afterward.
- **Accepted but no turn:** inspect the screen, book boundaries, reading mode, and `PageTurner` logs. A document switch or dialog appearing before dispatch cancels the queued command intentionally.

## Development tests

```sh
luajit tests/test_plugin.lua
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Lua tests use KOReader/socket doubles. Python tests exercise the laptop client with a real local HTTP fixture. Optional real LuaSocket transport tests (LuaSocket must be available to LuaJIT):

```sh
PAGETURNER_SOCKET_TESTS=1 python3 -m unittest discover -s tests -p 'test_*.py' -v
```

These do **not** validate Kindle firewall behavior, KOReader rendering, or device power behavior. Source research and design limits: [`docs/koreader-research.md`](docs/koreader-research.md). Product sequencing: [`roadmap.md`](roadmap.md).
