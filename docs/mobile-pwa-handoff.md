# Mobile PWA control — handoff

> Updated: 2026-09-19
> Working branch: `feat/mobile-pwa`
> Branch base: `main` at `2f3140f` (`changed plugin position in tools and added more network info`)
> State: Minimal diagnostic PWA harness and GitHub Pages workflow prepared; repository remote and Pages Actions configured, deployment/iPhone evidence pending.
> Canonical plan: [`../roadmap.md`](../roadmap.md), phase 2, **Mobile PWA control and reliability**.

## Resume here

Do not interpret this document or the local harness as evidence that the browser architecture already works. Continue on `feat/mobile-pwa`, not `main`; do not merge or alter the working Kindle installation without the owner's direction.

A minimal framework-free harness now exists in `mobile-pwa/`, and the owner approved GitHub Pages as its static HTTPS host. The repository remote is `iamads/pageturner`, `main` has been published, and Pages uses GitHub Actions. The next workstream is to deploy this feature branch, then run the **small actual-iPhone connectivity + foreground-wake-lock experiment** before a polished frontend or Kindle TLS/CORS architecture choice.

## Confirmed decisions

- Target phone: **iOS 26.6**, exactly as reported by the owner. Verify the actual device/build during testing; do not silently rewrite it to another version.
- Product: Mobile-friendly **PWA**, with user-entered Kindle **IP and port**, existing token authentication, and large **Next / Back** buttons.
- Operation: **Phone + Kindle only**. A running laptop bridge/proxy is not an acceptable runtime dependency.
- Wake behavior: **Prevent automatic screen lock while the PWA is visible**. There is no requirement to execute while backgrounded or manually locked.
- Preserve normal Kindle/KOReader behavior, its sleep settings, Wi-Fi management, and local navigation. A phone screen wake lock does not authorize keeping the Kindle awake.
- Retain shared-token access control. Do not remove it to simplify browser access.
- Sequence: Prove direct browser connectivity and screen wake lock first; build the small usable PWA second; validate two 30-minute mobile reading sessions; voice comes later.
- Work in the separate branch named above.

## Existing baseline

The owner reports that the initial MVP works on their Kindle, running **KOReader 2026.03**. The laptop observed the expected unauthenticated HTTP 401 from the plugin. The latest plugin moves Page Turner to the first item of the default Tools menu and shows Wi-Fi/IP/port connection details.

Do not overstate acceptance evidence:

- The exact initial 20 alternating visible-turn test and normal-reading regressions have not been reported in detail.
- The two 30-minute sessions have not been reported as completed.
- Latest menu/network-info changes still lack explicit on-device confirmation in the conversation.
- No Safari/Home Screen PWA, TLS, browser connectivity, or phone wake-lock tests have run.
- Phase 1 remains formally open. Mobile feasibility discovery is approved, but no prior gate is declared passed and no exception has been granted.

### Code map

| Path | Responsibility / relevance |
|---|---|
| `pageturner.koplugin/main.lua` | Listener/menu/lifecycle, foreground-reader guard, deferred `GotoViewRel(+1/-1)` dispatch, connection popup |
| `pageturner.koplugin/pageturner_http.lua` | Strict bodyless HTTP parsing, token validation, only POST `/next` and `/back`; **no CORS/preflight/static assets/health endpoint** |
| `pageturner.koplugin/pageturner_server.lua` | Nonblocking LuaSocket **plain HTTP** transport; four clients, 4 KiB headers, two-second client expiry; **no TLS** |
| `pageturner.koplugin/pageturner_firewall.lua` | Plugin-owned temporary Kindle firewall rules; cleanup/rollback |
| `pageturner.koplugin/pageturner_network.lua` | Read-only SSID and Wi-Fi IPv4 lookup |
| `tools/pageturner.py` | Laptop diagnostic client, existing token configuration, RTT JSON logs, no automatic retry |
| `tests/` | Lua plugin/network doubles, Python client tests, optional real LuaSocket transport tests |
| `README.md` | Install/update instructions and protocol/lifecycle limits |
| `mobile-pwa/` | Diagnostic installable shell: in-memory endpoint/token setup, one-shot controls, wake-lock lifecycle, redacted diagnostics; no hosting or device proof |
| `docs/koreader-research.md` | KOReader v2026.03 API evidence and prior test coverage |

### API/lifecycle contract to preserve

- Default endpoint: `http://<current-kindle-ip>:8088`; do not hard-code an IP learned in an earlier session.
- Bodyless `POST /next` and `POST /back`; `Authorization: Bearer <token>`.
- HTTP **202 means accepted**, not proof the displayed page moved. Dispatch occurs on a later UI tick and can be cancelled if the reader is no longer foregrounded.
- Missing/incorrect token: 401. Covered book or pending turn: 409. GET/unknown paths/bodies are not a supported connection-check API.
- Do not use page-turn requests as an automatic connectivity probe. A new non-mutating health/pairing endpoint would be a deliberate, documented/tested API change.
- Never automatically retry or replay an uncertain command after a timeout/reconnect. The first attempt may already have turned the page. Do not put navigation commands in a service-worker offline queue.
- Listener is opt-in per book, stops on normal sleep/close/exit, and may resume only through KOReader's existing lifecycle. It does not enable Wi-Fi or reset idle timers.

## Primary risk: a static HTTPS PWA cannot simply be pointed at the current HTTP API

A mobile button UI is easy compared with the browser security/deployment constraints:

1. Screen Wake Lock and service-worker capabilities require a **secure context**, normally trusted HTTPS on a phone accessing another device. An ordinary `http://192.168.x.x` Kindle origin is not the phone's localhost exception.
2. HTTPS-page fetches to plain HTTP normally hit **mixed-content restrictions**. Adding CORS headers does not by itself solve this. Verify the exact Safari/iOS local-network behavior rather than assume a version-specific exception works.
3. Cross-origin `Authorization` headers trigger an **OPTIONS preflight**. The current server rejects this and emits no CORS response headers. If the selected design is cross-origin, handle preflight deliberately without weakening authentication on the actual page-turn POSTs. Same-origin hosting can avoid CORS, not the secure-context requirement.
4. Adding an HTTP page to the Home Screen is not evidence that secure-context wake lock or offline caching works.
5. A self-signed certificate or clicking past a browser warning is not automatically a valid solution. Verify actual browser trust, hostname/IP certificate matching, secure-context status, and installed-PWA behavior together.

### Candidate approaches and decisions still open

- **Investigate first:** Trusted HTTPS on the Kindle, with same-origin PWA hosting or a separate HTTPS frontend calling it directly. Assess available TLS libraries/packaging and device resource cost before promising feasibility.
- A different direct phone-to-Kindle browser design is acceptable only if demonstrated on the target phone and consistent with authentication, PWA, and foreground wake-lock requirements.
- **Not selected:** HTTPS implementation, frontend stack, certificate issuance/trust provisioning, hostname/IP strategy, certificate renewal, DHCP-change handling, asset hosting, and service-worker cache/update policy.
- **Confirmed for the spike:** GitHub Pages may provide the external static HTTPS origin for initial loading/install. It serves only public shell assets and is not a command relay. The workflow publishes `mobile-pwa/` only and contains no token.
- **Still requires clarification before production commitment:** Whether use after installation must work with no internet and how much one-time Kindle certificate/profile/DNS setup the owner accepts.
- Token entry/pairing and persistence remain open. A browser cannot automatically read the laptop's `.pageturner-token`. Preserve authentication without embedding a shared secret in bundled frontend code.
- If certificate/IP constraints prevent the promised IP+port UX, explain the trade-off and obtain a decision instead of silently replacing it with hostname-only setup.
- A laptop bridge, cloud command relay, native app, or HTTP-only page without standard wake lock is **not an approved fallback**. If the direct PWA path fails, stop and bring the blocker back to the owner.

## Spike procedure (harness implemented; actual-device steps pending)

1. **Inspect target environment.** Record exact iPhone model/OS/build, Safari and Home Screen modes, Kindle model/firmware, KOReader version, normal phone Auto-Lock timeout, and current network. Do not change the timeout or Kindle sleep settings to make a test appear successful.
2. **Establish a minimal browser harness.** Log frontend origin, endpoint, `window.isSecureContext`, wake-lock availability/state, visibility changes, request status, and redacted browser errors. No production UI or framework investment yet.
3. **Test the browser-to-device path.** Diagnose mixed content, trust/certificate errors, local-network permissions, and preflight separately. Use scoped, reversible plugin changes on this branch where required. Confirm the laptop is not part of the command path; turn off development hosting for the final phone-only proof.
4. **Prove the combined deployment.** In the actual installed Home Screen PWA, authenticate and intentionally turn one page next and one page back, observing both on the Kindle. Demonstrate this from the same secure-context app that acquires the wake lock, not separate HTTP-control and HTTPS-wake demos.
5. **Test wake-lock lifecycle.** Start the visible reading session after a user action. Observe an idle interval longer than the phone's existing Auto-Lock timeout. Record elapsed time and actual screen behavior. Background and return, manually lock/unlock, and exercise rejection/release where possible. Reacquire only when visible and the user still wants the session active; otherwise show a truthful unavailable/released state. Include an explicit end-session/disable control.
6. **Review before frontend implementation.** Present direct-connectivity evidence, wake-lock evidence, and required hosting/trust/setup steps. Obtain owner acceptance of architecture/setup trade-offs. If blocked, document why and pause rather than quietly using a bridge or browser-security bypass.

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

Previous implementation session reported **39 passing local tests**: 21 Lua plugin, 9 Lua network, 6 Python client, 3 real LuaSocket transport integration tests. An additional source smoke check placed Page Turner first using the actual KOReader v2026.03 menu sorter/order. These are historical results, not rerun by this documentation-only handoff and not iPhone evidence.

From the repository root:

```sh
git branch --show-current   # expected: feat/mobile-pwa
git status --short
luajit tests/test_plugin.lua
luajit tests/test_network.lua
python3 -m unittest discover -s tests -p 'test_*.py' -v
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
- Do not deploy to the owner's Kindle, install trust profiles, publish hosting, expose ports publicly, or turn pages without the corresponding user direction. Local research can precede those actions.
- Keep changes scoped and reversible on `feat/mobile-pwa`; preserve the working plugin on `main`. No commit or merge was requested for this documentation turn.

## Source references and confidence

- [MDN Screen Wake Lock API](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API): Secure-context/visibility requirements and OS release/denial.
- [WebKit: Safari 18.4](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/): Home Screen web-app wake-lock support on iOS/iPadOS 18.4. This is prior platform evidence, not a test of the owner's reported iOS 26.6.
- [MDN mixed content](https://developer.mozilla.org/en-US/docs/Web/Security/Mixed_content): HTTPS-to-HTTP browser restrictions; re-check version-specific local-network behavior during the experiment.
- Repository HTTP/server modules establish that the current implementation lacks TLS, CORS, OPTIONS, static hosting, and a health endpoint.

**Immediate next action after resuming:** Confirm the `feat/mobile-pwa` Pages workflow deployment, then use its HTTPS URL for the documented installed-app experiment. Capture mixed-content, local-network, certificate, and preflight outcomes separately. Do not add Kindle TLS/CORS, choose a laptop bridge, or claim prior gates passed without that evidence and architecture review.
