# KOReader 2026.03: remote next/back feasibility

Inspected upstream source at tag **v2026.03**, matching the owner's reported version. Findings are source evidence, not an on-device compatibility claim.

## HTTP is a supported implementation pattern

[HTTP inspector plugin](https://github.com/koreader/koreader/blob/v2026.03/plugins/httpinspector.koplugin/main.lua):

- Runs a LuaSocket TCP server, registers it with `UIManager:insertZMQ`, and removes it with `removeZMQ`.
- Adds/removes Kindle iptables INPUT/OUTPUT rules for its listening port.
- Receives arbitrary high-level events over HTTP and defers dispatch with `UIManager:nextTick`.
- Stops on suspend/standby/close/exit and can restore its listener on resume.

This is strong precedent for a Kindle-hosted HTTP plugin. There is no reason yet to choose a relay, SSH-based input injection, or a phone-hosted polling server instead.

The inspector itself is **not** used as the shipped server: it exposes much broader inspection/execution capabilities than two page-turn commands need.

## Navigation

- [Auto-turn plugin](https://github.com/koreader/koreader/blob/v2026.03/plugins/autoturn.koplugin/main.lua) uses `self.ui:handleEvent(Event:new("GotoViewRel", distance))` when the reader is foregrounded.
- [ReaderRolling](https://github.com/koreader/koreader/blob/v2026.03/frontend/apps/reader/modules/readerrolling.lua) maps forward/back gestures to `onGotoViewRel(1/-1)` and handles this event for reflowable books.
- [ReaderPaging](https://github.com/koreader/koreader/blob/v2026.03/frontend/apps/reader/modules/readerpaging.lua) exposes the same event for paged documents.

Page Turner uses **+1 for next, -1 for back**. It does not inject touches/keys, modify rendering, or change reading mode. Existing scroll-mode and book-boundary semantics remain in control.

## UI responsiveness, sleep, and tokens

[SimpleTCPServer](https://github.com/koreader/koreader/blob/v2026.03/frontend/ui/message/simpletcpserver.lua) is useful precedent, but it can block while reading headers and debug-logs raw request headers. Raw logs would include the new bearer token.

The small `pageturner_server.lua` transport instead uses KOReader's already-bundled LuaSocket with:

- Zero socket timeout and incremental, capped header reads.
- At most four clients and bounded work each poll; two-second client deadlines.
- Partial-send handling and one response per closed connection.
- No raw request logging or threads.

[UIManager](https://github.com/koreader/koreader/blob/v2026.03/frontend/ui/uimanager.lua) polls registered message queues using its existing 50 ms `ZMQ_TIMEOUT`. Page Turner **does not change** that value or any global input timeout.

Crucially, `processZMQs()` executes the `InputEvent` hook if a queue returns an input event. HTTP inspector returns such an event after a response, resetting idle timers. Page Turner's `waitEvent()` instead always returns nil and defers the navigation handler directly. It neither resets inactivity with synthetic input nor calls power/Wi-Fi management APIs. The consequence is intentional: normal standby/suspend can make remote control unavailable.

Use [ui/time](https://github.com/koreader/koreader/blob/v2026.03/frontend/ui/time.lua)'s monotonic `time.now()` for device-side elapsed timing and Python `perf_counter()` for request RTT. There is no assumption of synchronized laptop/Kindle clocks.

## Minimal deployment choices

- Document-only plugin with an explicit start/stop menu and generated plugin-local config; no global settings writes.
- Default TCP port 8088; IPv4 listener on device interfaces. Trusted LAN only, no TLS, public exposure, or discovery service.
- Bodyless `POST /next` and `/back` with a random shared bearer token.
- HTTP 202 acknowledges acceptance before deferred dispatch; rendering is verified separately.
- Reject covered/no-longer-active readers and concurrent pending turns; never auto-retry uncertain requests.
- A private iptables chain avoids deleting another plugin's similar rules. Binding happens before firewall setup; failed startup rolls back. Only normal lifecycle cleanup is guaranteed—abrupt process termination can leave stale rules.

## Menu placement and connection details

- [ReaderMenu](https://github.com/koreader/koreader/blob/v2026.03/frontend/apps/reader/modules/readermenu.lua) loads a cached reader-menu order after collecting plugin items. [Plugin menu insertion](https://github.com/koreader/koreader/blob/v2026.03/frontend/ui/plugin/insert_menu.lua) uses this shared table for plugin placement. Page Turner inserts only its own ID at the front of `tools`, idempotently, and uses `sorting_hint = "tools"` as a fallback. Merely changing the hint would append it and could still put it on page two. Other items retain their relative order; no settings files are written. Explicit user order overrides still win.
- Manual start now displays a connection popup. The enabled connection-details entry reads a fresh snapshot when tapped; normal resume does not open a popup.
- [Kindle network manager methods](https://github.com/koreader/koreader/blob/v2026.03/frontend/device/kindle/device.lua) provide `getCurrentNetwork().ssid` through a read-only LIPC query and `getNetworkInterfaceName()` (`wlan0`). `isWifiOn()` is a sysfs query on Kindle. No scan or connection action is used.
- `getifaddrs` / numeric `getnameinfo`, already declared by KOReader's `ffi/posix_h`, provide an **up-interface Wi-Fi IPv4 address**, not USB/loopback/IPv6 or the listener's wildcard bind address. Allocated lists are freed even if conversion fails. This follows the read-only enumeration pattern in [Device:retrieveNetworkInfo](https://github.com/koreader/koreader/blob/v2026.03/frontend/device/generic/device.lua), without that method's gateway ping or localized-text parsing.
- Missing/unsupported information remains explicit rather than blocking listener startup or presenting a guessed URL. The popup never includes the bearer token.

## If it fails on the Kindle

Diagnose the specific layer before changing transports:

1. Plugin does not load: check folder placement, `crash.log`, dependency/API compatibility, and actual installed version.
2. Listener cannot bind: check port collision and LuaSocket availability.
3. Laptop cannot connect: check IP, ordinary sleep/Wi-Fi state, client isolation, and Kindle firewall setup. An alternative protocol does not automatically solve sleep or Wi-Fi isolation.
4. Accepted request does not move the book: verify foreground guard, actual `GotoViewRel` handlers, boundaries, and current reading mode.

Fallback candidates only if needed:

- Brief, isolated HTTP-inspector experiment to distinguish a custom-plugin bug from a device restriction; its broad surface is unsuitable as the permanent endpoint.
- Kindle-initiated polling to a laptop/phone relay if inbound connections are genuinely prohibited. This introduces latency, extra infrastructure, and power costs and still cannot wake a sleeping device without separate work.
- Existing SSH access as a diagnostic path, not a shipped arbitrary-shell command interface.

Any fallback that needs wake locks, automatic Wi-Fi changes, or modifications to normal reader behavior requires a new user decision. No fallback has been implemented or validated.

## Validation so far

- 21 Lua plugin tests with KOReader/socket doubles: protocol/authentication, fragmented I/O, bounded clients, partial sends, lifecycle cancellation, navigation direction, firewall ownership/rollback, configuration validation, menu placement, and connection-popup behavior.
- 9 network tests with OS/KOReader doubles: interface/IPv4 filtering, resource cleanup, unavailable data, Wi-Fi-off state, refreshed snapshots, and SSID display sanitization.
- Additional source smoke check using the actual v2026.03 `MenuSorter` and reader-menu order (other dependencies stubbed): Page Turner is the first Tools entry.
- 6 Python client tests: authenticated bodyless requests, timing/logging, configuration generation, failure handling, and no automatic retries.
- 3 real LuaSocket transport integration tests on the laptop: 20 alternating requests plus unauthorized rejection, fragmented/slow-client handling, and oversized-header/method rejection.
- Owner reports the initial MVP works on the Kindle. A laptop probe also received the expected unauthenticated HTTP 401 from the Kindle listener. The precise 20-visible-turn/regression gate and two-session trial have not been reported as completed. The new menu/network-details UI has not yet been verified on-device.
