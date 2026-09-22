# Mobile PWA control — handoff

> Updated: 2026-09-22
> Working branch: `feat/mobile-pwa`
> Branch base: `main` at `2f3140f` (`changed plugin position in tools and added more network info`)
> State: Private Tailscale Serve is selected. Current Tailscale 1.102.4 runs on the Paperwhite 3, the Kindle is registered, and Serve is active. Adding `--statedir=<extension>/state` fixed the observed `no TailscaleVarRoot` handshake failure; an unauthenticated iPhone HTTPS GET now reaches Page Turner and returns the expected 401. The private HTTPS/backend path is proven, while authenticated PWA control and wake lock remain untested. No Funnel/public endpoint was enabled.
> Canonical plan: [`../roadmap.md`](../roadmap.md), phase 2, **Mobile PWA control and reliability**.

## Current checkpoint — resume here first

The selected transport experiment is now **private Tailscale Serve**, not Funnel. The owner has installed and connected the official Tailscale app on the iPhone and does not use another phone VPN. The Kindle appears in the Tailscale admin console as `pageturner-kindle`; the one-off auth-key file was consumed and deleted. Persistent node state exists only on the installed Kindle under `/mnt/us/extensions/pageturner-tunnel/state/` and must not be overwritten with the repository's empty placeholder directory.

Target device evidence:

- Kindle Paperwhite 3, firmware 5.12.3, KOReader 2026.03 and KUAL.
- Linux `3.0.35-lab126`, ARMv7/32-bit Freescale i.MX6 SoloLite.
- About 503 MiB RAM, no swap, about 2.43 GiB free USB storage, no `/dev/net/tun`, KOReader CA bundle present.
- Official Tailscale **1.102.4 ARM** executables both report their versions successfully despite the kernel being below current Go's supported Linux minimum.
- A 15-second logged-out daemon test in `--tun=userspace-networking --state=mem:` remained healthy at about 13.6 MiB RSS and six threads; local API worked and cleanup succeeded. This is bounded evidence, not official platform support or a battery/session result.
- Persistent registration eventually succeeded. The first registration attempt exposed a wrapper bug: old-Kindle process verification misclassified a live daemon and unlinked its socket. Corrected scripts use `/proc/<pid>/exe`; restarting the Kindle safely cleared orphan processes before the successful retry.

Latest result: the revised Serve configurator completed successfully and reported the private HTTPS endpoint proxying to `http://127.0.0.1:8088`. Initial iPhone handshakes reached the Kindle but failed with `no TailscaleVarRoot`. Tailscale 1.102.4 source showed managed certificates require a writable var root; the wrapper's explicit state-file parent was not auto-detected because it is named `state`, not `tailscale`. After `start-private-tailscale.sh` added `--statedir=<extension>/state` and the daemon was restarted/reconfigured, Safari reached `https://<private-ts-host>/next` and received the expected unauthenticated **401**. This proves private TLS termination, Serve's loopback proxy and Page Turner reachability; it does not yet prove authenticated commands or visible page turns through the PWA.

Immediate continuation:

1. The PWA now accepts one endpoint field in either direct IPv4 form (default HTTP/8088) or private `*.ts.net` form (default HTTPS/443), with an optional inline `:port`. Run its endpoint unit tests and deploy it.
2. Launch the updated PWA from the actual iPhone Home Screen with Tailscale connected; enter the private hostname and existing Page Turner token.
3. With a book foregrounded and all Kindle menus closed, send one Next and one Back, confirming exactly one visible turn each. Do not repeat an uncertain command.
4. Test wrong/missing token and Tailscale-disconnected behavior, then the foreground wake-lock lifecycle.
5. Separately run the roadmap's non-blocking Android/Chrome experiment against the direct Kindle IP first; do not require Tailscale there unless evidence shows it is needed.
6. Preserve the Kindle's registered `state/` directory and keep Funnel disabled.

Detailed implementation decisions and history: [`tailscale-private-serve-spec.md`](tailscale-private-serve-spec.md). Operator instructions: [`../kindle-kual/README.md`](../kindle-kual/README.md).

## Strategies tried and results

| Strategy | Result / decision |
|---|---|
| Laptop → Kindle plain HTTP | Owner reports MVP works; unauthenticated probe returned expected 401. Full 20-turn/regression gate remains unreported. |
| GitHub Pages HTTPS PWA → Kindle HTTP from desktop Chrome | Works after exact-origin CORS/preflight support; desktop browser can control the Kindle. |
| Direct iPhone navigation to Kindle HTTP | Reaches the listener and returns 401, proving phone LAN reachability. |
| GitHub Pages HTTPS PWA → Kindle HTTP from iPhone WebKit | Fails in about 4 ms with no Kindle transport log; secure-page/private-HTTP browser policy is the likely blocker. Plain HTTP PWA path closed for the tested iPhone only; Android remains a non-blocking direct-HTTP experiment. |
| Manual Kindle hostname/certificate/DNS | Rejected due changing Wi-Fi IP and setup/renewal complexity. |
| iOS Shortcut or native iOS app | Rejected as the primary product path; PWA and foreground wake lock remain required. |
| Tailscale Funnel | Researched and briefly chosen, then superseded. Its only major UX advantage here is no phone VPN; public exposure and hardening are unnecessary because the owner accepts the phone app. Never enabled. |
| Private Tailscale Serve | Selected. Adding `--statedir` fixed managed certificate storage. Safari on the tailnet now reaches Page Turner through private HTTPS and receives the expected unauthenticated 401. Authenticated PWA commands remain to be tested. |
| Custom secure relay / WebRTC | Documented alternatives, not implemented. Preserve as fallbacks only if private Serve fails for a diagnosed reason. |
| Voice-command processing | Research completed separately in `pwa-voice-command-research.md`; no microphone/voice implementation. Apple Voice Control is the least-work trial; sherpa-onnx phrase spotting is the preferred free embedded candidate. Voice remains after mobile transport/wake validation. |

## KUAL extension created

Repository package: `kindle-kual/pageturner-tunnel/`. Installed location: `/mnt/us/extensions/pageturner-tunnel/`.

Do not copy the entire repository folder over a registered Kindle: repository `state/`, `private/`, and `logs/` contain placeholders, while the Kindle's `state/tailscaled.state` is its private node identity. Auth keys, state and logs are ignored by Git. A root-level `auth.key` is also ignored; any consumed local copy should be deleted rather than retained.

KUAL actions and underlying behavior:

| KUAL action | Key command / effect |
|---|---|
| Check compatibility | Read-only kernel/CPU/memory/storage/TUN/CA inventory; writes `/mnt/us/pageturner-compatibility.txt`. |
| Test current Tailscale launch | `tailscale version` and `tailscaled --version`; no daemon/login. |
| Test temporary Tailscale daemon | Starts `tailscaled --tun=userspace-networking --state=mem: --socket=/tmp/pageturner-tailscaled-smoke.sock --port=0`, checks local API/resources, then removes it. |
| Start private Tailscale | Starts the isolated persistent daemon with `--tun=userspace-networking --state=<extension>/state/tailscaled.state --statedir=<extension>/state --socket=/tmp/pageturner-tailscaled.sock --port=0`; the state directory also holds managed TLS certificate material. It does not enable SSH/routes/DNS proxying. |
| Register Kindle with auth key | Runs `tailscale --socket=<socket> up --auth-key=file:<private/auth.key> --hostname=pageturner-kindle --accept-routes=false --accept-dns=false --ssh=false`; successful one-off key file is deleted. Do not run again after registration unless deliberately reauthenticating. |
| Show private Tailscale status | Runs `tailscale --socket=<socket> status`, shows KUAL output and writes `logs/status.log`. |
| Stop private Tailscale | Stops only the PID owned by this extension. Preserves node state and Serve configuration. |
| Configure private HTTPS Serve | Starts/reuses Tailscale, waits for connection, runs `tailscale serve reset`, then `tailscale serve --bg --https=443 http://127.0.0.1:8088`. Never calls Funnel. |
| Show private Serve status | Runs `tailscale serve status` with a visible 15-second wait counter, displays active/not configured/failed/timeout and URL/proxy on Kindle, writes timestamped `logs/serve-status.log`. |
| Disable private Serve | Runs `tailscale serve reset`; does not stop or unregister Tailscale. |

Normal operating order after registration:

```text
Start private Tailscale
Configure private HTTPS Serve   # now auto-starts, so explicit Start is optional
Show private Serve status
open KOReader/book → Start Page Turner
connect iPhone Tailscale → use/test private HTTPS endpoint
```

Shutdown/rollback order:

```text
Disable private Serve
Stop private Tailscale
```

Removing the node entirely additionally requires deleting/revoking `pageturner-kindle` in the Tailscale admin console and removing the Kindle's persistent `state/`; that rollback has not been selected or tested yet.

## Resume here

Do not interpret the local harness or successful Tailscale registration as evidence that the complete browser architecture works. Continue on `feat/mobile-pwa`, not `main`; do not merge or overwrite the Kindle's registered extension state. The owner has authorized the private Serve experiment and the device/account changes listed above, but not Funnel, unrelated network features, or page turns without coordination.

A minimal framework-free harness exists in `mobile-pwa/`, and GitHub Pages serves it at `https://iamads.github.io/pageturner/`. The older `iamads/iamads.github.io` repository still tracks `CNAME` containing `abhijeet.de` on `master`; remove it there before a future legacy build if detachment should persist. Direct phone HTTP reaches the Kindle, but secure-PWA HTTP fetch did not reach the plugin on tested iPhone WebKit. Private Serve now provides working managed TLS and loopback proxy reachability on iPhone without manual Kindle certificates or public exposure. Authenticated PWA control/wake lock remain unproven, and Android direct HTTP remains unknown.

## Confirmed decisions

- Target phone: **iOS 26.6**, exactly as reported by the owner. Verify the actual device/build during testing; do not silently rewrite it to another version.
- Product: Mobile-friendly **PWA**, with one user-entered endpoint supporting a direct Kindle **IPv4 address** or private **Tailscale URL**, optional inline port, existing token authentication, and large **Next / Back** buttons.
- Operation: **Phone + Kindle only**. A running laptop bridge/proxy is not an acceptable runtime dependency. Internet connectivity during reading is acceptable.
- Wake behavior: **Prevent automatic screen lock while the PWA is visible**. Standard foreground wake lock is non-negotiable; there is no requirement to execute while backgrounded or manually locked.
- Preserve normal Kindle/KOReader behavior, its sleep settings, Wi-Fi management, and local navigation. A phone screen wake lock does not authorize keeping the Kindle awake.
- Retain shared-token access control. Do not remove it to simplify browser access.
- Sequence: Prove browser connectivity and screen wake lock first; build the small usable PWA second; validate two 30-minute mobile reading sessions; voice comes later.
- Rejected as primary solutions: iOS Shortcut, native iOS app, and manual hostname/certificate/DNS setup. A Kindle-hosted plain-HTTP page is a last resort because it cannot provide standard wake lock.
- **Private Tailscale Serve is selected for the spike.** The owner accepts enabling Tailscale on the iPhone and has no other phone VPN. Funnel/public exposure is explicitly out of current scope.
- The owner approved Kindle compatibility checks, official ARM binaries, isolated KUAL packaging, tailnet registration, and private Serve configuration. Ask before unrelated device/account changes, Funnel, policy broadening, or destructive rollback.
- Work in the separate branch named above.

## Existing baseline

The owner reports that the initial MVP works on their Kindle, running **KOReader 2026.03**. The laptop observed the expected unauthenticated HTTP 401 from the plugin. The latest plugin moves Page Turner to the first item of the default Tools menu and shows Wi-Fi/IP/port connection details.

Do not overstate acceptance evidence:

- After the scoped CORS update was installed, the owner reports the Pages PWA works from desktop Chrome, including actual Kindle control. CORS and authenticated direct HTTP are therefore validated in that desktop environment.
- The owner reports failure from iPhone Safari and Firefox Focus. Focus diagnostics show `https://iamads.github.io` is secure, Wake Lock/service worker APIs exist, browser display mode is active, and the HTTP Kindle fetch fails in 4 ms with `TypeError: Load failed`. Direct HTTP navigation returned/logged 401 at 21:54, but the PWA tap at 21:56 produced no transport log before listener stop at 21:57. This establishes LAN/listener reachability and no observed delivery for that PWA attempt; it strongly suggests browser/OS blocking but is not the exact WebKit policy error. The tested Safari/Focus path is WebKit-based; another iOS browser brand should not automatically be treated as an independent engine test. No installed/Home Screen run or active wake-lock test has passed.
- The exact initial 20 alternating visible-turn test and normal-reading regressions have not been reported in detail.
- The two 30-minute sessions have not been reported as completed.
- Latest menu/network-info changes still lack explicit on-device confirmation in the conversation.
- Safari/Focus browser-mode connectivity has failed; no Home Screen connectivity, TLS, or active phone wake-lock test has passed.
- Phase 1 remains formally open. Mobile feasibility discovery is approved, but no prior gate is declared passed and no exception has been granted.

### Code map

| Path | Responsibility / relevance |
|---|---|
| `pageturner.koplugin/main.lua` | Listener/menu/lifecycle, foreground-reader guard, deferred `GotoViewRel(+1/-1)` dispatch, connection popup |
| `pageturner.koplugin/pageturner_http.lua` | Strict bodyless HTTP parsing, token validation, scoped Pages-origin OPTIONS/CORS for only `/next` and `/back`; no static assets/health endpoint |
| `pageturner.koplugin/pageturner_server.lua` | Nonblocking LuaSocket **plain HTTP** transport; four clients, 4 KiB headers, two-second client expiry; **no TLS** |
| `pageturner.koplugin/pageturner_firewall.lua` | Plugin-owned temporary Kindle firewall rules; cleanup/rollback |
| `pageturner.koplugin/pageturner_network.lua` | Read-only SSID and Wi-Fi IPv4 lookup |
| `tools/pageturner.py` | Laptop diagnostic client, existing token configuration, RTT JSON logs, no automatic retry |
| `tests/` | Lua plugin/network doubles, Python client tests, optional real LuaSocket transport tests |
| `README.md` | Install/update instructions and protocol/lifecycle limits |
| `mobile-pwa/` | Diagnostic installable shell: in-memory endpoint/token setup, one-shot controls, wake-lock lifecycle, redacted diagnostics; no device proof |
| `docs/mobile-pwa-hosting-strategies.md` | Consolidated S01–S25 catalogue of every brainstormed strategy, pros/cons, requirements fit, evidence, and decision status |
| `docs/tailscale-research.md` | Original Serve/Funnel comparison, official constraints, community precedent and compatibility/security risks |
| `docs/tailscale-private-serve-spec.md` | Current selected transport decisions, device evidence, registration history, acceptance criteria and unresolved rollback choice |
| `kindle-kual/pageturner-tunnel/` | Isolated KUAL extension: diagnostics, current ARM binaries (locally ignored), persistent daemon registration, private Serve controls and Kindle-screen status |
| `kindle-kual/README.md` | Exact copy paths, account-key registration procedure, KUAL commands, logs and private Serve operation |
| `docs/pwa-voice-command-research.md` | Free/on-device voice options and recommendation; research only, deferred until transport/wake proof |
| `docs/koreader-research.md` | KOReader v2026.03 API evidence and prior test coverage |

### API/lifecycle contract to preserve

- Direct default endpoint: `http://<current-kindle-ip>:8088`; private iPhone endpoint: `https://<private-ts-host>` on 443. The PWA accepts either form with an optional inline port; do not hard-code an IP learned in an earlier session.
- Bodyless `POST /next` and `POST /back`; `Authorization: Bearer <token>`.
- Browser preflight is restricted to exact origin `https://iamads.github.io`, `/next` or `/back`, POST, and Authorization. Valid OPTIONS returns 204 and never turns a page; actual POST still requires the token. Any future PWA origin change must update this allowlist deliberately.
- HTTP **202 means accepted**, not proof the displayed page moved. Dispatch occurs on a later UI tick and can be cancelled if the reader is no longer foregrounded.
- Missing/incorrect token: 401. Covered book or pending turn: 409. GET/unknown paths/bodies are not a supported connection-check API.
- Do not use page-turn requests as an automatic connectivity probe. A new non-mutating health/pairing endpoint would be a deliberate, documented/tested API change.
- Never automatically retry or replay an uncertain command after a timeout/reconnect. The first attempt may already have turned the page. Do not put navigation commands in a service-worker offline queue.
- Listener is opt-in per book, stops on normal sleep/close/exit, and may resume only through KOReader's existing lifecycle. It does not enable Wi-Fi or reset idle timers.

## Primary risk: retain a secure PWA without changing-IP certificate management

The observed plain-HTTP results and constraints are:

1. Desktop Chrome works after scoped CORS, because Chromium supports its local-network HTTP permission path.
2. On iPhone WebKit, direct HTTP navigation reaches the listener and returns/logs 401, while the Pages PWA fetch produces no plugin connection. CORS, token entry, Wi-Fi isolation, and listener reachability are therefore not the remaining blocker.
3. Standard Screen Wake Lock still requires the PWA's secure context and is non-negotiable. A Kindle-hosted HTTP page is not equivalent.
4. An IP-address certificate is rejected because the Kindle address changes. Manual hostname/DNS/certificate management is also rejected.
5. A fetch-based candidate needs a trusted HTTPS endpoint independent of Wi-Fi IP changes. A different browser-supported secure transport, such as a WebRTC data channel or connection through a relay, is also possible in principle. Preserve authentication, foreground wake lock, no replay, and no running laptop.

Tailscale Serve/Funnel can potentially supply that stable `*.ts.net` HTTPS endpoint while proxying to the existing local HTTP plugin. This avoids implementing TLS in Lua but introduces a persistent Kindle daemon, external account/control-plane dependency, credentials, resource use, and new lifecycle/security work.

### Selected approach and remaining work

The broad comparison remains in [`mobile-pwa-hosting-strategies.md`](mobile-pwa-hosting-strategies.md); historical Tailscale research is in [`tailscale-research.md`](tailscale-research.md). The current decision record is [`tailscale-private-serve-spec.md`](tailscale-private-serve-spec.md).

- **Selected:** private Tailscale Serve HTTPS. Both devices join the tailnet; the bearer token and scoped CORS remain required application controls.
- **Superseded:** Funnel. It was never enabled and must remain off.
- **Validated:** current ARM binaries launch; userspace daemon can run within a bounded test; persistent one-off-key registration succeeds; iPhone Tailscale is connected.
- **Validated:** Serve configuration, managed certificate issuance after adding `--statedir`, private iPhone HTTPS, Serve's loopback proxy and unauthenticated Page Turner reachability (expected 401).
- **Implemented, not yet device-validated:** one PWA endpoint field accepts direct IPv4 (HTTP/8088 default) or private `*.ts.net` (HTTPS/443 default), each with an optional inline port.
- **Not yet validated:** authenticated proxy requests/page turns, the updated PWA on iPhone, Android direct HTTP, foreground wake lock with commands, sleep/reconnect behavior, battery impact and long reading sessions.
- **Implementation constraint:** no TUN exists, so Kindle Tailscale must use `--tun=userspace-networking`; managed certificate material requires the explicit persistent `--statedir`. Do not include tokens in URLs or storage and do not replay uncertain commands.
- **Plugin behavior to preserve:** authenticated bodyless next/back, exact Pages-origin CORS, strict 4 KiB parsing, foreground-reader guard and no retry. Do not loosen parsing preemptively; observe actual Serve requests first.
- **Fallbacks only after diagnosis:** custom relay or WebRTC. Raw browser sockets, plain HTTP, Shortcut/native/manual-certificate paths remain unsuitable or rejected under current scope.

## Active private-Serve spike procedure

1. Keep the now-proven private Serve/TLS configuration and registered state intact.
2. Test and deploy the dual-mode PWA endpoint update.
3. Return to KOReader, open a book, start Page Turner on port 8088 and close dialogs/menus.
4. In the iPhone Home Screen PWA with Tailscale connected, configure the private hostname (443 is optional) and existing token.
5. Send only the coordinated authenticated test commands. Do not change token, CORS, timeout uncertainty or service-worker no-replay behavior.
6. In the actual installed Home Screen PWA, send one Next and one Back, verifying exactly one visible turn each. Test missing/wrong token and Tailscale-disconnected behavior.
7. Test foreground wake lock past the existing Auto-Lock interval, visibility transitions, manual lock/unlock and truthful recovery without replay.
8. Measure daemon resources during KOReader/Serve operation, then test stop/start, normal sleep/resume and two 30-minute reading sessions before any phase-pass claim.

The OS may deny or revoke a wake lock (visibility, power policy, battery, etc.). Do not promise the browser is immortal, use artificial audio/video to keep it running, or try to defeat manual locking. Reopening the app should recover normally without replaying page commands.

## Outcome gates and carry-over checks

These reference the canonical roadmap, not a second independent roadmap:

- **P2-G0 — proposed concrete spike checks:** Direct authenticated next/back and foreground wake lock work together in the intended installed PWA on the actual iPhone, with no laptop dependency. Owner accepts setup/trust requirements before UI investment.
- **P2-O1:** Two **30-minute mobile-controlled reading sessions**, no missed/duplicate turns or normal-KOReader disruption. Record command counts, RTT, visibility, and wake-lock events. The <100 ms delivery goal remains diagnostic, not a hard gate.
- **P2-O2:** Interruption recovery does not generate extra/replayed turns or lose reading position; failures and wake-lock release are understandable.
- **P2-O3:** Retain token protection and existing Kindle reading/power/network behavior. No public exposure, global settings change, or runtime laptop dependency.
- **P2-O4:** Documented install/launch, endpoint/token setup, direct bidirectional turns, relaunch, and unauthorized-command rejection on the target phone. Detailed checks are proposed until reviewed with the spike results.
- **P2-O5:** No auto-lock during the observed foreground idle interval while the OS grants the lock; honest release/denial state and return/reacquisition behavior. Manual lock/background execution is outside scope.
- Resolve phase 1's unreported 20-turn/regression evidence or explicitly document an owner-approved exception before claiming formal advancement. Do not mark phases complete based on “MVP works” or a 202 response alone.
- Voice remains deferred until the mobile-control/session gate is explicitly accepted.

## Test baseline and commands

Current non-optional application validation reports **65 passing tests**: 32 Lua plugin, 9 Lua network, 6 Python client, and 18 PWA endpoint-parser tests. Three real LuaSocket transport tests previously passed but could not be rerun in the latest environment because local LuaSocket is unavailable. KUAL shell scripts pass local `sh -n`, menu JSON/path checks and `git diff --check`; these checks do not emulate old Kindle BusyBox. On-device evidence now covers binary launch, a 15-second userspace daemon run, cleanup, persistent registration, managed private HTTPS and an expected 401 through Serve's loopback proxy—but not authenticated PWA commands, iPhone wake behavior, battery use or reading-session reliability.

From the repository root:

```sh
git branch --show-current   # expected: feat/mobile-pwa
git status --short
luajit tests/test_plugin.lua
luajit tests/test_network.lua
python3 -m unittest discover -s tests -p 'test_*.py' -v
node --test tests/test_pwa_endpoint.mjs
```

The three optional socket-integration tests are skipped unless LuaSocket is installed/configured for local LuaJIT and explicitly enabled:

```sh
PAGETURNER_SOCKET_TESTS=1 python3 -m unittest discover -s tests -p 'test_*.py' -v
```

KOReader's bundled LuaSocket on the Kindle is separate from the developer laptop's module setup. Do not depend on a prior agent's temporary build directories. Add browser tests for connection validation, auth failures, in-flight request handling, uncertainty/no-retry behavior, and wake-lock/visibility transitions after choosing a viable design. Mocks do not validate iOS security restrictions or real screen wake behavior.

## Secrets and operational safety

- Local ignored files: `pageturner.koplugin/config.lua` and `.pageturner-token`. They already exist on the current development machine; do not regenerate or print their token during handoff/testing.
- They are **not tracked** and will not appear in a fresh clone. If absent on another machine, obtain pairing/configuration deliberately; do not assume an empty token is acceptable.
- Do not commit configuration secrets, copy tokens into browser logs/URLs, bundle tokens in a public PWA, or ship the Kindle configuration as a static asset.
- Tailscale auth keys, daemon state, machine identity, certificate private keys, tailnet details and generated Serve configuration must remain untracked. `.gitignore` covers the extension's private/state/log files, downloaded binaries and a root `/auth.key`; do not rely on ignore rules as secret deletion.
- A consumed root-level `auth.key` currently exists locally as an ignored file. Do not read, print or commit it; delete it when the owner no longer needs the local copy. The Kindle copy was consumed/deleted after registration.
- The owner authorized the installed iPhone VPN, Kindle tailnet registration and private Serve experiment. Funnel/public exposure, SSH, exit nodes, accepted routes, global KOReader proxy changes, policy broadening and destructive node-state removal remain unauthorized.
- Keep changes scoped and reversible on `feat/mobile-pwa`; preserve the working plugin on `main`. No commit or merge was requested for this documentation turn.

## Source references and confidence

- [MDN Screen Wake Lock API](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API): Secure-context/visibility requirements and OS release/denial.
- [WebKit: Safari 18.4](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/): Home Screen web-app wake-lock support on iOS/iPadOS 18.4. This is prior platform evidence, not a test of the owner's reported iOS 26.6.
- [MDN mixed content](https://developer.mozilla.org/en-US/docs/Web/Security/Mixed_content): HTTPS-to-HTTP browser restrictions.
- [Tailscale Serve](https://tailscale.com/kb/1312/serve), [Funnel](https://tailscale.com/kb/1223/funnel), [HTTPS](https://tailscale.com/kb/1153/enabling-https), [static Linux binaries](https://tailscale.com/kb/1053/install-static), [userspace networking](https://tailscale.com/kb/1112/userspace-networking), and [iOS](https://tailscale.com/kb/1020/install-ios).
- Community precedent: [KOReader Tailscale plugin](https://github.com/victoria-riley-barnett/koreader-tailscale) at inspected commit `5422ff9`, and [Kindle KUAL extension](https://github.com/mitanshu7/tailscale_kual) at `ccd35eb`. Community code and README claims are not target-device evidence.
- Current Page Turner branch has scoped Pages-origin CORS and no TLS/static hosting/health endpoint.

**Immediate next action after resuming:** Run the endpoint parser tests, deploy the dual-mode PWA, then perform one coordinated authenticated Next and Back through private Serve from the installed iPhone app. Android direct-IP testing is explicitly non-blocking and follows separately. Preserve registered state, token controls and no-retry semantics; do not enable Funnel.
