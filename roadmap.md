# Product Roadmap

> Status: Discovery
> Current phase: Kindle remote-control feasibility — acceptance evidence open; next-phase mobile PWA discovery approved
> Last updated: 2026-09-22

## Vision
### Original vision
> I want to build a plugin for ko reader that allows me to turn pages
>
> The full vision would involve users phone listening for specific voice commands like next and back and turn page on kindle
>
> But the very first thing that we need to do is to build a plugin for koreader and I should be able to load it onto my kindle. And from laptop I should be able to send commands to go to next page or back page
>
> The next and back interaction needs research how we could do that. For the very first version I would like to try run a server on kindle and then do some http requests to call next and back, if this is not possible brainstorm other ways to do this.

### Current vision
- Confirmed: Enable phone voice commands to turn pages in KOReader on Kindle.
- Confirmed: Start with a loadable KOReader plugin and laptop-issued next/back commands; try a Kindle-hosted HTTP server first.
- Confirmed: Research page-turn integration and consider alternatives if HTTP is infeasible.
- Confirmed initial scope (2026-09-18): Build minimal programmatic next/back, shared-token protection, and diagnostic timing before broader roadmap work.
- Confirmed revision (2026-09-19): Next, build a mobile PWA with Kindle IP/port configuration and Next/Back buttons, retaining token authentication. First prove direct iPhone-to-Kindle connectivity and foreground screen wake lock on the actual phone, then build the usable interface. Voice remains a later step.
- Confirmed: Development for this next phase began on `feat/mobile-pwa`; current repository work may subsequently be integrated on `main`. The operational handoff is [docs/mobile-pwa-handoff.md](docs/mobile-pwa-handoff.md).
- Confirmed revision (2026-09-22): Mobile transport is platform-adaptive. The tested iPhone requires private Tailscale Serve, but the PWA must also accept a direct Kindle IPv4 endpoint because Android may support same-Wi-Fi HTTP without Tailscale. Android validation is a non-blocking learning objective, not a requirement for the owner/iPhone phase gate.
- Earlier revision (2026-09-22; scanner strategy superseded below): Kindle-displayed JSON QR with PWA camera scanning, per-start in-memory tokens, verified Serve/local fallback and manual entry.
- Confirmed replacement (2026-09-22): Native phone cameras scan a normal link to `https://iamads.github.io/pageturner/`. Version/endpoint/token are URL-encoded in its fragment (not sent to GitHub), immediately removed by the app, and held only in memory. Automatically verify with authenticated non-mutating `POST /connect`; display inline success/failure and explicit retry. Remove PWA camera/decoder responsibilities; manual input moves to a modal. Token lifecycle, route selection, Next/Back, wake lock and private transport remain unchanged. Native-camera browser opening is not a guarantee of installed-PWA handoff. Approved specification: [camera-link pairing](docs/camera-link-pairing-spec.md).

### Target users and core job
- Confirmed: The owner will test laptop-to-Kindle page turning on their own Kindle first.
- Confirmed: Personal use while reading in bed; phone voice control should remove the need to touch the Kindle to turn pages.
- Confirmed: Possible later plugin distribution, not a current commitment or broader-user validation requirement.
- Confirmed next use case: Owner reads in bed and uses large phone buttons without a running laptop, while the visible PWA prevents automatic screen lock when the OS grants a wake lock.

### Product principles
- Confirmed: Establish device-level control before adding voice input.
- Proposed: Reuse KOReader's supported events and networking facilities where practical.
- Confirmed: Everything outside the added remote next/back capability should continue working as it already does. Preserve existing KOReader settings, local controls, navigation behavior, and normal lifecycle behavior.
- Proposed implementation guardrail: Keep remote input from blocking reading or destabilizing KOReader; reuse normal reader navigation rather than modifying it.
- Proposed: Start on a trusted local network without public internet exposure.
- Confirmed: Phone + Kindle only for mobile operation; no running laptop bridge. Internet connectivity during reading is acceptable. Use the least-dependent transport proven for each phone platform: direct same-Wi-Fi HTTP where browser policy permits it, otherwise private Tailscale Serve. Public exposure remains unapproved.
- Confirmed: Phone wake behavior means preventing auto-lock while the PWA is visible, not keeping it executing in the background or while the phone is manually locked. Do not promise immunity to OS wake-lock revocation.

### Explicit non-goals
- Confirmed for the first version and next mobile phase: Phone voice recognition.
- Confirmed for the mobile phase: Laptop-dependent control, background/locked-screen execution, and modifications to the Kindle's sleep behavior. A foreground phone Screen Wake Lock request is in scope; changing global phone Auto-Lock settings is not the proposed implementation.
- Confirmed: Unrelated KOReader behavior changes. Acceptance of awake-device testing is not permission to change global sleep or power settings automatically.
- Proposed for the first version: Stock Kindle reader support, internet remote access, broad device compatibility, distribution infrastructure, monetization.

### Constraints
- Confirmed: Target application is KOReader on Kindle, not the stock reader.
- Confirmed: KOReader is already installed, version 2026.03 (owner-reported).
- Confirmed: Laptop and Kindle will share Wi-Fi; keeping the Kindle awake with Wi-Fi enabled is acceptable for the first experiment.
- Confirmed: Desired command delivery is <100 ms, excluding e-ink refresh. Later clarification: Capture round-trip logs, but do not block v1 on a numeric latency gate or optimization.
- Confirmed: Owner can copy plugin files onto the Kindle; transfer method is not a blocker.
- Confirmed: A simple shared token is acceptable for access control.
- Unknown: Kindle model, firmware, and available development time.
- Confirmed: Target phone OS is **iOS 26.6**, as reported by the owner. Verify the exact OS/build and browser behavior on the actual device during the spike; do not substitute a different version in planning.
- Confirmed: Prevent phone auto-lock only while the PWA is visible. Background or locked-phone operation is not required for this phase.
- Confirmed revision (2026-09-19): Standard foreground Screen Wake Lock remains non-negotiable. iOS Shortcut and native-app approaches are rejected; a Kindle-hosted HTTP page is last-resort only; manual hostname/certificate/DNS setup is rejected. Unknown: Tailscale Serve versus Funnel viability, phone VPN acceptance, Kindle compatibility/resources, public-exposure acceptance, token pairing/storage UX, and privacy/background-listening requirements for the later voice phase.

## Strategic context
### Evidence already available
- At discovery start, the project directory was empty. A minimal plugin, laptop client, install instructions, and local tests are now implemented. Owner now reports “Mvp works”; detailed gate results remain unreported.
- 2026-09-18: The Kindle listener responded to an unauthenticated laptop probe with the expected HTTP 401. This verifies reachability/authentication rejection, not a page turn.
- Owner requests easier menu access and visible Wi-Fi name/IP/port after startup. Implemented as first entry in the default Tools menu and a fresh, read-only connection-details popup; on-device UI verification is pending. This is an in-scope usability refinement, not a strategy or phase-gate change.
- Implementation: `pageturner.koplugin/`, `tools/pageturner.py`, and `README.md`. HTTP exposes authenticated bodyless POST next/back plus the approved non-mutating `/connect` check, with diagnostic timing and no sleep/Wi-Fi/settings changes.
- Source compatibility was checked against **v2026.03**, not only moving master. Findings and references: [KOReader research](docs/koreader-research.md).
- Local validation: 21 Lua plugin tests, 9 Lua network tests, 6 Python client tests, and 3 real LuaSocket transport integration tests passed. A smoke check using the actual v2026.03 menu sorter/order also confirmed first Tools placement. Mocks/source checks do not replace actual Kindle UI or power-behavior tests.
- Owner reports KOReader 2026.03 already running on their Kindle and confirms same-Wi-Fi testing with the device awake.
- Owner-reported MVP success supports initial HTTP/navigation feasibility. Exact command count, latency distribution, and regression/session results are still unknown.
- Upstream source inspected on 2026-09-18 (moving `master`, not the owner's installed version): [HTTP inspector](https://github.com/koreader/koreader/blob/master/plugins/httpinspector.koplugin/main.lua) already runs an HTTP listener using `ui/message/simpletcpserver`, registers it with the UI manager, adds/removes Kindle firewall rules, and exposes event dispatch over HTTP. This is strong implementation precedent, not an on-device test.
- [Auto-turn plugin](https://github.com/koreader/koreader/blob/master/plugins/autoturn.koplugin/main.lua) invokes `self.ui:handleEvent(Event:new("GotoViewRel", 1))` through its default distance. [Dispatcher](https://github.com/koreader/koreader/blob/master/frontend/dispatcher.lua) exposes this event as “Turn pages” with signed numeric distances. Proposed next/back mapping: +1/-1; verify behavior in the owner's reading mode and book format.
- Proposed: Use HTTP inspector only as a short, trusted-network diagnostic if available, then reuse the relevant patterns in a narrow next/back plugin. Its arbitrary event/method inspection surface is broader than this product needs.

- PWA source research: [Screen Wake Lock API](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API) requires a secure context and an active/visible document; the OS can deny/release it. [WebKit Safari 18.4 notes](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/) document Home Screen web-app wake-lock support. This is not execution evidence for the owner's reported iOS 26.6.
- Browser transport evidence: After narrowly scoped Pages-origin CORS/OPTIONS was installed, the GitHub Pages PWA successfully controlled the Kindle from desktop Chrome. On the iPhone, direct navigation to `http://192.168.0.102:8088/next` returned the expected 401 and logged at 21:54, proving phone-to-Kindle HTTP reachability without turning a page. A PWA tap at 21:56 produced a 4 ms `TypeError: Load failed` and no plugin connection/request log before the listener stopped at 21:57. This isolates the current failure to iPhone WebKit blocking before network delivery; it is not token, CORS-response, Wi-Fi isolation, or Kindle reachability. Safari and Firefox Focus both use WebKit and are not independent transport engines.
- 2026-09-19: A framework-free diagnostic PWA shell now exists in `mobile-pwa/`. It records secure-context/install/wake-lock state, accepts endpoint/token in memory, sends commands once with no replay, and never service-worker-queues command requests. Local syntax/static-serving checks pass. After the owner removed the old account-level Pages domain and the workflow was redeployed, `https://iamads.github.io/pageturner/` and all shell assets returned HTTP 200 over HTTPS. The older user-site repository still tracks `CNAME` with `abhijeet.de` on its `master` Pages source branch, creating recurrence risk on a future legacy rebuild.
- 2026-09-22 private iPhone transport evidence: Tailscale 1.102.4 runs in userspace mode on the Paperwhite 3 and private Serve is active. Adding an explicit writable `--statedir` fixed `no TailscaleVarRoot`; Safari then reached the Serve URL and Page Turner returned the expected unauthenticated 401. This proves private TLS and loopback backend reachability, not yet authenticated PWA turns or wake lock. No Android PWA test has been performed, so Android direct-HTTP capability remains unknown.
- KOReader v2026.03 source includes `QRWidget`, `QRMessage`, bundled `ffi/qrencode`, and an existing QR Clipboard plugin. This is strong source evidence that the Kindle can render the proposed pairing payload; the Page Turner composition, phone scan and on-device readability still require tests.
- 2026-09-19 desktop diagnostic: Chrome 151 on macOS loaded the Pages app as a secure browser context with Wake Lock and service-worker APIs available, but `fetch` from `https://iamads.github.io` to `http://192.168.0.102:8088` failed with `TypeError: Failed to fetch` after 2 ms. An independent non-mutating HTTP probe received 401 in 284 ms, proving basic listener reachability only. Exact DevTools policy text was not captured, so the failing browser layer and whether any request reached the Kindle are unknown. H7 remains untested because wake lock was available but inactive.
- Research conclusion for the tested devices: [Chrome Local Network Access](https://developer.chrome.com/blog/local-network-access) permits the desktop Chrome HTTPS→local-HTTP path. On the iPhone, no plugin connection was observed for the Pages fetch despite successful direct HTTP navigation; browser/OS policy is strongly implicated, though the exact Safari policy error remains uncaptured. Kindle HTTPS is a solution for the current fetch design, not the only possible secure-PWA transport: an outbound secure relay or WebRTC data channel could also preserve wake lock. Raw UDP/TCP sockets are not available to an ordinary Safari PWA. WebRTC is a conceptual alternative, not researched or validated on this Kindle.

### Critical uncertainties
| ID | Uncertainty / hypothesis | Why it matters | How it will be tested | Status |
|---|---|---|---|---|
| H1 | A custom plugin can be installed and run on the owner's Kindle | Prerequisite for all later work | Inspect device setup and load a minimal plugin | Owner reports MVP works; plugin menu/startup observed by owner |
| H2 | KOReader can accept laptop HTTP requests without blocking the UI | Determines initial transport | Inspect upstream networking and run an on-device spike | HTTP reachability observed; responsiveness guardrails need detailed evidence |
| H3 | Next/back can safely invoke reader page navigation | Requests alone do not prove useful control | Inspect navigation events; verify visible page changes in both directions | Owner reports MVP works; exact 20-turn/regression results unreported |
| H4 | Wireless connectivity remains usable during real reading | Sleep/power behavior may undermine practical use | Reading-session and reconnect tests | Unknown |
| H5 | Voice commands offer repeated value with acceptable recognition errors | Determines whether voice input is justified after button control | Owner use-case interview, then voice prototype and reading trials | Unknown; deferred until after mobile button control |
| H6 | A secure-context PWA can control the Kindle without a laptop/relay using a platform-appropriate endpoint | Determines viable mobile architecture without forcing one phone's workaround onto every platform | Test direct LAN HTTP and, where required, private Tailscale HTTPS in actual installed/Home Screen contexts | Owner reports the deployed private-Serve camera-link setup “works.” Exact browser/installed mode and bidirectional command details were not separately reported; Android direct HTTP remains unknown |
| H7 | The visible PWA can prevent auto-lock and safely recover after visibility changes | Required for the mobile reading experience | Actual iPhone idle, background/return, and wake-lock denial/release tests | iPhone Focus reports API available in secure browser context, but lock was inactive; acquisition/idle lifecycle untested |
| H8 | The owner can pair/authenticate without leaking the token or excessive setup | Repeated manual token transcription is unsafe and cumbersome | Test native-camera link opening, fragment removal, authenticated check, manual modal and session-token lifecycle | Deployed camera-link setup works in the owner's environment. Detailed fragment/manual-modal/token-lifecycle evidence remains unreported |
| H9 | Current Tailscale can run acceptably on the owner's Kindle and provide private Serve HTTPS | Required iPhone workaround avoids changing-IP certificate management while preserving secure PWA/wake lock | Reversible compatibility/resource/HTTPS proxy spike and reading-session observation | Binary, userspace daemon, registration, certificate issuance and unauthenticated Serve proxy reachability pass; authenticated commands, sleep/session reliability and battery remain unknown |
| H10 | Android Chrome may permit the Pages PWA to control the Kindle directly over same-Wi-Fi HTTP | Determines whether Android users can avoid installing/running Tailscale | On an available Android device, test browser and installed-PWA direct IP, CORS/preflight, one Next/Back and wake lock; compare Tailscale only if useful | Unknown; non-blocking for the current owner/iPhone gate |
| H11 | Kindle QR pairing can remove endpoint/token transcription without leaking credentials or issuing accidental commands | Determines whether setup is fast and safe enough for repeated reading sessions | Display a versioned URL QR plus route text, scan using the native camera, verify inline authentication without a turn, and test malformed/stale links and lifecycle | Native-camera replacement is deployed and owner-confirmed working. Handoff context, malformed/stale links and lifecycle still need detailed evidence |

## Roadmap overview
| Phase | Purpose | Exit outcome | Confidence | State |
|---|---|---|---|---|
| 1. Kindle remote-control feasibility | Prove installation, request handling, and actual page navigation | Owner demonstrates both directions from a laptop without breaking local reading | Medium; owner reports MVP success | In-device use reported; gate evidence incomplete; usability refinement |
| 2. Mobile PWA control and reliability | Prove direct phone control, foreground wake lock, and usable reading sessions | Owner controls Kindle from the installed PWA without a laptop; two 30-minute sessions meet navigation/wake/recovery guardrails | Low until iPhone feasibility spike | Confirmed next scope; discovery experiment first |
| 3. Phone voice proof of value | Test hands-free reading rather than merely speech recognition | Owner repeatedly completes useful reading sessions with acceptable command errors | Low | Directional |
| 4. Broader-user validation, if desired | Learn whether others can adopt and benefit | Target users independently set up and repeatedly use the tool | Low | Optional; possible later plugin distribution |

## Current phase: Kindle remote-control feasibility
### Purpose and strategic question
Can the owner load a KOReader plugin on their Kindle and use laptop commands to navigate an open book, preferably via a Kindle-hosted HTTP listener?

### Target users and use case
Confirmed: The owner, their Kindle running KOReader 2026.03, and their laptop on the same Wi-Fi. The Kindle may remain awake with Wi-Fi enabled for this experiment.

### Hypotheses
H1–H3 are prerequisites. H4 is an early operational risk.

### Bets and experiments
1. Record Kindle model/firmware when available and verify compatibility with owner-reported KOReader 2026.03. Plugin file-copy access, same-Wi-Fi, and awake-device testing are confirmed; model details need not block source research.
2. Validate upstream findings against the installed KOReader version: HTTP inspector's simple TCP server/UI-manager integration and Kindle firewall lifecycle; auto-turn's `GotoViewRel` navigation. Inspect server request limits, lifecycle, and navigation guards before implementation. Optionally test existing HTTP inspector briefly on a trusted network before building the narrow plugin.
3. Load a minimal custom plugin and demonstrate an explicit start/stop lifecycle.
4. Try next/back requests with an open book; compare HTTP response with the visible navigation result.
5. If inbound HTTP is blocked or unsuitable, diagnose why before choosing alternatives: adapt existing remote-control facilities, use Kindle-initiated polling to a laptop/phone relay, or evaluate another supported transport. These are candidates, not verified capabilities.

### Measurement and instrumentation
- Proposed: Record hardware/software versions, install steps, request commands, request/dispatch logs, observed page position, and UI responsiveness.
- Confirmed: Test 20 alternating next/back commands and verify actual page turns plus continued touch navigation.
- Proposed: Also test requests with no book open and listener shutdown.
- Confirmed latency boundary: Command delivery to the Kindle, excluding completed e-ink refresh.
- Implemented diagnostic measurement: Laptop monotonic-clock timing from HTTP request start through the full application acknowledgement, including TCP setup; optional JSONL logging. No automatic retries or synchronized-clock assumption. No <100 ms pass/fail gate for v1.
- Implemented: HTTP 202 acknowledges acceptance for asynchronous page-turn dispatch. Validate the actual visible turn separately; HTTP acknowledgement is not evidence that rendering completed. Device logs distinguish acceptance, dispatch, and cancellation.

### Required outcomes and guardrails
- P1-O1: Confirmed installation milestone: Owner can install/load the plugin on their Kindle. Proposed additional check: It loads again after restarting KOReader.
- P1-O2 (confirmed): In one initial test of 20 alternating next/back commands, every request produces exactly one correct visible page turn, checked against displayed book position away from book boundaries.
- P1-O3: Confirmed: Existing KOReader behavior must remain intact, including local touch navigation. Proposed regression checks: Open/close a book, touch next/back, menus, saved reading position, and stop/disable the plugin; verify these behave as before, with no crash, UI freeze, or unexpected settings changes. Listener/firewall changes should be scoped to the enabled server and cleaned up on stop. These checks provide bounded evidence, not proof of every KOReader feature.
- P1-O4: Confirmed aspiration: <100 ms delivery, excluding e-ink refresh. Confirmed revision: Do not block the first version on latency optimization; add round-trip verification logs and evaluate measurements later. The proposed mandatory <100 ms gate is withdrawn.
- Confirmed: Simple shared-token access control is acceptable. Proposed gate P1-O5: Missing/incorrect token requests cause no page turn; only authenticated next/back commands are accepted, and the token is not written to logs.
- Proposed: Keep the listener off public networks. Plain HTTP plus a token is suitable only for the agreed trusted-network experiment; it does not encrypt the token or prevent interception by an attacker who can observe traffic.

### Exit gate
- Functional acceptance: Installation, 20 alternating next/back commands producing exactly one correct turn each, and preserved existing KOReader behavior. Proposed supplemental checks: Restart/load, listener cleanup, and unauthorized-command rejection. Record timing as diagnostic evidence, not a performance blocker.
- Partial evidence: Owner reports MVP works and listener reachability is observed. The exact 20-command result and normal-behavior checks remain unreported; no phase advancement is inferred.
- Proposed decision owner: Project owner reviews evidence and explicitly authorizes moving to phase 2.

### Pass, mixed, and fail decisions
- Pass: Retain the demonstrated transport and assess real-session reliability.
- Mixed: If navigation works but listener or lifecycle is unreliable, remain in this phase and fix or narrow the experiment.
- Fail: If HTTP is infeasible, compare fallback transports against the diagnosed limitation. If custom plugins cannot run, resolve device prerequisites before continuing.

### Dependencies and constraints
KOReader 2026.03 is already installed; plugin file-copy access, same-Wi-Fi, and awake-device testing are confirmed. Device model and firmware remain unknown; record during setup if needed rather than blocking research. Upstream compatibility must be checked against the installed version.

### Non-goals
Voice recognition and phone UI. Proposed: Polished distribution and multi-device support. The <100 ms delivery target does not require e-ink refresh to complete in that time.

## Next phase: Mobile PWA control and reliability
### Purpose and strategic question
Can the owner control their Kindle from a usable iPhone PWA through the proven private Serve path, keep the phone screen awake while that PWA is visible, and rely on the controls throughout reading in bed—without a running laptop? Separately, can Android use the simpler direct-LAN path without making that exploration block the owner/iPhone outcome?

Confirmed revision on 2026-09-19: Replaces **Usable laptop-controlled reading** with mobile button control plus reliability validation. Retains the two 30-minute sessions and no-regression guardrails; moves them onto the phone. This is a sequencing revision, not a declaration that phase 1 passed.

### Target users and use case
Confirmed primary target: Owner, iPhone on reported iOS 26.6, and Kindle running KOReader 2026.03. Enter the private Tailscale endpoint and existing authentication token, then use Next/Back buttons while the PWA remains visible. No laptop is required during use.

Non-blocking exploratory target: An available Android phone running Chrome, on the same Wi-Fi as the Kindle. Enter the direct Kindle IPv4 endpoint first; use Tailscale only as a fallback/comparison if direct browser policy prevents control.

### Hypotheses
H6 and H7 remain the primary iPhone risks; H8 governs pairing/setup. H10 tests Android direct-LAN behavior without gating iPhone progress. H4 and reliable one-request/one-turn behavior remain relevant. Voice value (H5) is deferred, not a prerequisite for button control.

### Bets and experiments
1. **Connectivity/wake-lock spike first (confirmed sequencing).** On the actual iPhone, record OS/build, Safari versus installed Home Screen context, secure-context status, frontend origin, Kindle endpoint, local-network permissions, and any TLS/mixed-content/CORS errors. Prove authenticated next/back and wake lock together in the intended deployment; do not treat an HTTPS wake-lock demo and an unrelated HTTP control page as a combined success.
2. Plain HTTP is disproven for the tested iPhone WebKit path. Private Tailscale Serve is the selected iPhone transport; private TLS and unauthenticated proxy reachability pass. Keep Funnel/public exposure out of scope and preserve no-laptop operation.
3. Support both endpoint modes in one PWA field: direct IPv4 with optional inline port (default HTTP/8088), and private `*.ts.net` hostname/URL with optional inline port (default HTTPS/443). Reject paths/query/credentials; retain in-memory token handling and no replay.
4. Add QR pairing. On each manual Start, obtain 32 bytes from the OS random source, retain the encoded token only for that listener session (including normal suspend/resume), and invalidate it on manual Stop, book close or KOReader exit. Check active Serve with a bounded non-blocking operation and select it only when its proxy target matches the current plugin port; otherwise use current local IPv4. Display a versioned HTTPS project-link QR with URL-encoded endpoint/token in its fragment, route/endpoint text and a menu action to reopen it.
5. Replace the earlier PWA camera/decoder experiment with native-camera link opening. Extract and clear the fragment, strictly validate credentials, perform a three-second authenticated `/connect` check without turning pages, and enable controls only on success. Display failure/retry inline. Keep masked manual entry in a modal; no app credential persistence. Update plugin/PWA together and invalidate the old scanner cache.
6. Run a non-blocking Android Chrome/Home Screen experiment against direct HTTP first. Record Android/device/browser versions, local-network permissions, CORS/preflight delivery, one coordinated Next/Back, wake lock and plugin logs. Test Tailscale only as fallback/comparison; do not infer Android behavior from desktop Chrome or iPhone WebKit.
7. If using distinct origins, retain narrowly scoped preflight/CORS behavior while keeping actual commands token-authenticated. Do not remove authentication, use opaque `no-cors` requests, or assume local-network permission bypasses browser policy.
8. Continue the minimal mobile UI: endpoint/authentication setup, large Next/Back controls, honest connection/error feedback, and visible wake-lock state. Installation/bootstrap, offline shell behavior, and token persistence remain design decisions.
9. Acquire a screen wake lock for the visible control session, observe release/denial, and attempt reacquisition on return to visibility as allowed by the platform. Provide an explicit end/disable action and release when appropriate; no background-execution guarantee, global Auto-Lock changes, or audio/video keep-alive tricks.
10. Run the carried-over two 30-minute reading sessions on the primary iPhone, plus interruption cases: wrong token, unreachable/sleeping Kindle, open Kindle menu, changed endpoint, failed request, app background/return, and phone manual lock. Never replay uncertain page-turn commands after recovery.

### Measurement and instrumentation
- Capture the exact origin/endpoint/security context and browser errors, plus Home Screen install/launch evidence on the target phone. Keep tokens out of logs, query strings, shared URLs, screenshots, and source control. The private pairing fragment is the only intended URL credential carrier and must be removed immediately.
- Record button taps, HTTP acknowledgements, corresponding observed page changes, RTT, errors, and recovery actions; HTTP 202 still means acceptance, not completed rendering.
- Record wake-lock acquisition/release/denial and visibility changes. Establish the phone's existing Auto-Lock interval without changing it, then observe an idle foreground interval longer than that timeout; record elapsed time and whether the screen stayed awake.
- Session evidence: Duration, command counts, missed/duplicate/incorrect turns, normal KOReader behavior, interruptions, and manual intervention. Keep timing diagnostic; no new <100 ms gate.
- Pairing evidence: QR generation/display result, selected route and endpoint, token lifecycle boundary, native-camera link recognition/opening, actual browser versus installed display mode, time from Start to inline Connected, fragment removal, manual modal behavior, malformed/stale link handling, timeout/retry, and confirmation that only the non-mutating connection check occurs on arrival. Never log or screenshot the link/token.
- Android experiment evidence (non-blocking): device/Android/Chrome versions, browser versus installed mode, endpoint mode, QR/camera result, permission and preflight behavior, plugin delivery logs, visible Next/Back results, wake-lock state, and whether Tailscale was necessary.

### Required outcomes and guardrails
- P2-O1 (confirmed, revised platform): Owner completes **two 30-minute phone-controlled reading sessions** with no missed/duplicate turns or disruption to normal KOReader behavior. Record command counts and timing.
- P2-O2 (retained proposed operational criterion): Recovery from tested interruptions is understandable, with no replayed/extra page turns or lost reading position. Wake-lock denial/release is shown honestly, not as an active lock.
- P2-O3 (confirmed): Existing Kindle/KOReader behavior and authentication remain intact. No Kindle sleep-setting changes, remote wake, automatic Wi-Fi changes, or laptop dependency. Regression and security checks remain required evidence; precise battery budget is not a blocker.
- P2-O4 (confirmed capability; revised pairing measurement): Owner scans the Kindle QR with the target phone's native camera, opens the project link, sees inline authenticated connection success without a page turn, verifies route/endpoint, and produces one correct next and back turn with no running laptop. Record actual display mode; native-camera handoff to the installed PWA is not guaranteed. Separately validate install/launch and use the manual modal when required for installed-context testing. Repeat after a new manual Start to prove rotation; prior tokens and malformed links cannot enable valid control or turn pages. Reload requires rescanning/manual entry. Installed-context wake/control gates below remain open.
- P2-O5 (confirmed capability; proposed measurement): While the installed PWA is visible and the OS grants a wake lock, the phone stays awake through an idle interval longer than its configured Auto-Lock timeout, including idle periods in the session trials. Background/manual lock and OS revocation may end the lock; return/reacquisition or an actionable unavailable state must be observed. No promise of unrestricted background operation.

### Non-blocking learning objective
- P2-L1: On an available Android/Chrome device, determine with recorded evidence whether direct same-Wi-Fi HTTP supports authenticated Next/Back and foreground wake lock from the Pages PWA. A failure informs Android transport fallback; missing or negative Android evidence does not block P2-G0 or phase exit for the primary owner/iPhone use case.

### Exit gate
- **P2-G0 — feasibility checkpoint before UI investment:** Owner and developer review actual-device evidence that direct authenticated control and foreground wake lock coexist in the intended installed PWA, along with explicit acceptance of any hosting/certificate/trust setup. Proposed exact spike checks are P2-O4's bidirectional demonstration and P2-O5's idle/visibility experiment. If blocked, stop and choose a revised plan with the owner.
- **Phase exit before voice:** Owner reviews P2-O1–O5, including both 30-minute sessions and interruption/regression results, and explicitly accepts the supported limits. No advance based merely on building a PWA or successful HTTP responses.
- Phase 1's exact 20-command/regression evidence remains open. Mobile feasibility discovery is authorized without asserting that previous acceptance passed; resolve or explicitly document an owner-approved exception before formal phase advancement.

### Pass, mixed, and fail decisions
- Spike passes: Select the evidenced direct architecture after owner approval of setup costs; implement the small control UI, then run the session gate.
- Phase passes: Proceed to a separate phone voice experiment after explicit owner acceptance.
- Mixed: Fix or characterize connection, certificate, wake-lock, or reading disruptions before advancing. Retest on the phone; do not quietly weaken the phone-only or secure-context requirements.
- Fails: Document the precise blocker and return to the owner. A laptop bridge, plain-HTTP page without standard wake lock, or native app is a scope change, not an automatic fallback. Leave the working plugin available.

### Dependencies and constraints
- Confirmed target: Owner-reported iOS 26.6, KOReader 2026.03, phone+Kindle-only operation, per-manual-start bearer token, and foreground-only phone wake lock.
- The KOReader API remains HTTP-only, bodyless authenticated POST next/back, now with an authenticated non-mutating `POST /connect` (204 on success) and narrowly scoped Pages-origin OPTIONS/CORS for these three routes only. The check bypasses foreground-reader/pending-turn guards without mutating them; page-turn semantics are unchanged. Private Serve supplies TLS for the iPhone. Retain both direct IPv4 and private Tailscale endpoint modes.
- Confirmed for the spike: GitHub Pages hosts the static PWA shell at `https://iamads.github.io/pageturner/`; it is not a command relay and contains no token. Live page and shell-asset HTTP checks pass. The stale `CNAME` in the older user-site repository should be removed separately if the old domain must stay detached.
- Confirmed: Internet connectivity during reading is acceptable; offline operation is not required for this spike. Manual hostname/certificate/DNS management is rejected.
- Confirmed: Private Tailscale Serve is selected and technically reachable for the iPhone; Funnel remains prohibited. Tailscale selection during pairing must verify active Serve for the current backend rather than merely detecting a daemon/socket. Kindle model/kernel/resources and current-binary compatibility have bounded evidence in the handoff. Unknowns remain authenticated PWA control, wake/session/battery reliability, Android direct-LAN behavior, production frontend architecture, and token pairing/storage. Current comparisons: [Mobile PWA hosting strategies](docs/mobile-pwa-hosting-strategies.md) and [Tailscale research](docs/tailscale-research.md).
- Current integrated work is on `main`; operational handoff: [Mobile PWA handoff](docs/mobile-pwa-handoff.md).

### Non-goals
Voice/microphone access, locked-screen/background execution, native app packaging, running laptop/proxy dependency, public Kindle exposure, expanded commands, broad recruitment, and unrelated reader/power changes. Static asset hosting and certificate setup are unresolved—not silently approved cloud infrastructure.

## Later direction
### Phone voice proof of value
- Directional purpose: Let the owner say next/back on a phone and continue reading without touching the Kindle.
- Entry trigger: Mobile button-control and reliability gate accepted on the actual phone; then confirm the separate voice interaction/recognition requirements.
- Candidate outcomes: Repeated useful reading sessions; correct intended turns, few false activations, and acceptable listening/power/privacy behavior.
- Measurement and gate: Proposed owner review of observed sessions and command-error logs against thresholds set before the prototype trial; proceed only after explicit acceptance. Mixed results lead to recognition/interaction iteration; failure prompts reconsidering voice versus simpler controls.
- Major unknowns: Phone OS, foreground/background operation, offline recognition, ambient noise, accidental triggers, and preferred listening interaction.
- Confidence: Low.

### Broader-user validation, if desired
- Directional purpose: Determine whether a defined audience can independently adopt and repeatedly benefit.
- Entry trigger: Owner demonstrates repeated value and explicitly chooses a broader audience.
- Candidate outcomes: Independent installation and repeat use for the audience's real reading task; cohort, observation period, and thresholds defined before recruitment.
- Measurement and gate: Proposed owner review of onboarding observations and repeated-use evidence; expand only if agreed outcomes pass. Mixed results prompt targeted onboarding/use-case iteration; failure keeps this a personal tool or revises the audience.
- Major unknowns: Audience, distribution, support burden, compatibility scope, and any commercial intent.
- Confidence: Low.

## Implementation checkpoint
- Owner reports minimal v1 works on their Kindle; detailed acceptance/regression evidence remains incomplete.
- Requested usability update: Page Turner first in default Tools (no More tools hop); startup and on-demand connection popup shows Wi-Fi name, Wi-Fi IPv4, port, and URL when available. Read-only queries; no token shown, networking/power/settings changes, or popup on automatic resume. New UI awaits owner testing.
- Chosen implementation details (not separate product approvals): Manual listener per open book, default port 8088, plugin-local token config, foreground-reader guard, no automatic retries, private temporary firewall chain, normal suspend/standby cleanup and normal-resume restoration when previously enabled.
- No sleep/settings writes, Wi-Fi activation, remote wake, arbitrary event endpoint, phone code, or distribution machinery.
- Pending owner evidence: Exact 20 visible bidirectional turns, preserved local behavior and listener cleanup; verify updated menu placement and displayed Wi-Fi/IP/port after copying the UI update. Hardware model/firmware can be recorded during that test.
- 2026-09-19: Owner approved the mobile PWA phase revision and feasibility-first sequence, with foreground-only wake lock on reported iOS 26.6 and no running laptop. Branch `feat/mobile-pwa` was created from `main` at `2f3140f`.
- 2026-09-19: Added the minimal `mobile-pwa/` feasibility harness before choosing a production architecture. It includes install metadata/offline shell caching, endpoint configuration, one-shot Next/Back requests, foreground wake-lock lifecycle controls, and token-redacted diagnostics. GitHub Pages is now live at the expected `github.io` project URL after custom-domain removal and redeployment. No Kindle API/TLS/CORS behavior changed; actual-iPhone combined connectivity/wake evidence remains the next checkpoint.
- 2026-09-22: Private Tailscale Serve now terminates trusted HTTPS and reaches Page Turner's expected 401 boundary from Safari after adding persistent certificate storage. PWA endpoint handling accepts either direct IPv4 (HTTP/8088 default) or private `*.ts.net` (HTTPS/443 default), with optional inline ports. Android direct-LAN testing is explicitly non-blocking.
- 2026-09-22 historical scanner implementation (superseded): per-manual-start tokens, automatic/reopenable JSON QR, PWA camera decoding and manual fallback.
- 2026-09-22 camera-link replacement is deployed at `https://iamads.github.io/pageturner/` and installed on the owner's Kindle; the owner reports “works.” It uses fragment-only credentials cleared on arrival, authenticated `/connect` with inline status/retry, a manual modal, no PWA camera/decoder, and cache v4. Live assets were checked and local validation remains 87 tests. Exact browser/installed context, token lifecycle, wake lock, interruption and long-session evidence remain open; no phase transition.
- Logging/CORS experiment: Added token-safe transport diagnostics and scoped Pages-origin CORS. Desktop Chrome control succeeds. On iPhone, direct HTTP navigation returns/logs 401, but a PWA tap while the listener remains active creates no transport log and fails in 4 ms. This closes the plain-HTTP PWA experiment as incompatible with tested WebKit; CORS remains useful for a future cross-origin HTTPS endpoint. Local validation: 37 plugin/pairing tests, 9 network tests, 6 Python client tests, and 20 PWA endpoint/payload tests pass. Three optional real-socket tests could not run because local LuaSocket is unavailable.
- No phase has been declared passed. The broader roadmap still contains directional/unconfirmed decisions, so its overall status remains Discovery.

## Phase transition record
| Date | From | To | Gate evidence | Decision owner |
|---|---|---|---|---|
| — | — | — | No transitions; discovery only | — |

## Open questions
- [x] KOReader installed: owner reports version 2026.03.
- [x] Owner can copy plugin files to the Kindle.
- [ ] Record Kindle model/firmware during setup if relevant to compatibility; not a blocker for research.
- [x] Personal reading in bed; possible later plugin distribution.
- [x] Shared Wi-Fi; awake Kindle with Wi-Fi enabled acceptable for the first experiment.
- [x] Simple shared-token access control is acceptable.
- [x] Do not change sleep settings or unrelated behavior; focus on programmatic next/back.
- [ ] Confirm supplemental security checks and trusted-network deployment assumptions during device setup.
- [x] Defined first functional acceptance: Install plugin; 20 alternating commands, each producing one correct turn; touch navigation still works. This checked item records the criterion, not a completed trial.
- [ ] Record exact phase 1 command/regression results or an explicit owner-approved exception before formal advancement.
- [x] Latency boundary: <100 ms for command delivery to Kindle, not completed e-ink refresh.
- [x] Log round-trip timing; defer latency optimization and do not impose a <100 ms first-version gate.
- [x] Next reliability trial: Two 30-minute sessions, no missed/duplicate turns or normal-behavior disruption.
- [ ] Time/resource constraints and acceptable manual setup?
- [x] Mobile target: Owner-reported iOS 26.6; phone+Kindle only; prevent auto-lock while the PWA is visible, not background/locked-phone execution.
- [x] Approved next-phase replacement: Mobile PWA control + reliability; connectivity/wake-lock spike first; work on a separate branch.
- [ ] Verify exact iPhone OS/build and installed-PWA behavior. Supplied Firefox Focus UA reports `iPhone OS 18_7`, `FxiOS/155`, and `Version/26.4`, which conflicts with the earlier owner-reported iOS 26.6 and is not authoritative OS-settings evidence. Browser mode is confirmed; Home Screen mode remains untested.
- [x] Correlated iPhone test: direct HTTP navigation returned/logged 401; PWA tap produced no transport line while listener was active. Plain-HTTP secure-PWA path is blocked before plugin delivery in tested WebKit.
- [x] Selected private Tailscale Serve for the tested iPhone; Funnel/public exposure remains prohibited.
- [x] Recorded Paperwhite 3, firmware 5.12.3, Linux 3.0.35, ARMv7, memory/storage and bounded current-binary/userspace-daemon compatibility.
- [x] Owner installed/connected the Tailscale iOS app and private HTTPS reaches Page Turner's authentication boundary.
- [ ] Run the non-blocking Android Chrome/Home Screen direct-HTTP experiment and record whether Tailscale is needed on that platform.
- [ ] If Funnel is considered, explicitly revisit the no-public-exposure and direct-connection outcome language before implementation.
- [x] Static spike hosting/bootstrap: GitHub Pages is live at `https://iamads.github.io/pageturner/`; remove the stale older-site `CNAME` separately to avoid recurrence.
- [x] Camera-link replacement approved: per-start token, reopenable Kindle URL QR, fragment credentials, native-camera opening, safe authenticated check with inline results/retry, and manual-entry modal; remove PWA scanner.
- [x] Owner confirms the deployed native-camera pairing setup works on the actual Kindle/phone environment; live cache-v4 app assets verified.
- [ ] Record detailed browser/installed context, fragment removal, modal entry, token rotation/stale rejection and wake-lock evidence; the concise “works” report does not establish each separately.
- [ ] Refine privacy/offline recognition and background listening requirements only when the later voice phase is considered.
- [x] Preserve existing KOReader behavior outside remote next/back controls.
- [ ] Confirm bounded regression checks, proposed phases, outcome measures, gates, and non-goals.

## Change log
| Date | Change | Reason / evidence | Affected phases | Confirmed by |
|---|---|---|---|---|
| 2026-09-18 | Created discovery draft; separated owner-stated vision from proposed experiments and gates | Initial request; empty project directory | All | Original vision and HTTP-first sequence: user; remaining proposals unconfirmed |
| 2026-09-18 | Recorded upstream HTTP listener, Kindle firewall handling, and page-navigation event precedent | Inspection of HTTP inspector, auto-turn, and dispatcher source; no target-device execution | 1 | Source evidence; reuse and diagnostic approach proposed |
| 2026-09-18 | Recorded installed KOReader 2026.03, same-Wi-Fi/awake-device constraints, personal reading-in-bed use case, accepted 20-command functional test, and desired ~100 ms latency | Owner's first interview answers; latency semantics still unclear | 1–3; optional distribution | User |
| 2026-09-18 | Added explicit preservation of existing KOReader behavior; proposed bounded regression checks and no automatic global sleep-setting changes | User: “everything else should work as it already does” | All | User for preservation requirement; checks proposed |
| 2026-09-18 | Confirmed plugin file-copy access, <100 ms command-delivery target excluding refresh, and shared-token acceptance; proposed acknowledgement timing and token rejection checks | Owner's second interview answers | 1–2 | User for constraints; measurement/gate details proposed |
| 2026-09-18 | Paused discovery and authorized minimal implementation; removed latency hard-gate proposal, accepted diagnostic timing and two 30-minute reliability sessions, reinforced no sleep/unrelated changes | User asks to build first version now | 1–2 | User; full roadmap remains unconfirmed |
| 2026-09-18 | Implemented minimal HTTP plugin/client, documented v2026.03 source compatibility, and passed 27 local tests; left device gate open | Lua mocks, Python HTTP fixture, and real LuaSocket transport tests; no Kindle execution | 1 | Implementation evidence recorded by assistant; owner device validation pending |
| 2026-09-18 | Recorded owner-reported MVP success and observed HTTP reachability; implemented requested earlier menu placement and read-only Wi-Fi/IP/port details; 39 local tests pass | Owner's usability feedback after using the MVP; upstream menu/network API research and tests. No strategy/gate change or phase transition | 1; helps next-phase setup | User for MVP report and requested UX; assistant for local implementation/test evidence |
| 2026-09-19 | Replaced proposed laptop-only reliability phase with mobile PWA control + reliability; retained two 30-minute sessions and Kindle guardrails; added direct-connectivity/wake-lock feasibility checkpoint, kept voice later and prior evidence gaps open | User confirmed iOS 26.6, foreground auto-lock prevention only, phone+Kindle-only operation, and the proposed phase revision. Current HTTP/CORS/secure-context constraints require research first | 2 and voice entry; no phase transition | User explicitly approved scope/sequencing; detailed spike criteria and architecture remain proposed/unverified |
| 2026-09-19 | Created `feat/mobile-pwa` from `main` at `2f3140f` and prepared `docs/mobile-pwa-handoff.md`; no PWA code or device changes | User requested separate branch, roadmap update, and handoff before continuing | 2 | User |
| 2026-09-19 | Added a minimal diagnostic PWA harness without selecting hosting or changing the Kindle API; no device evidence or gate transition claimed | Authorized feasibility-first work; local shell/syntax checks and all existing non-optional tests pass, but actual HTTPS/iPhone behavior remains untested | 2 | User authorized mobile-PWA work; implementation evidence recorded by assistant |
| 2026-09-19 | Selected GitHub Pages for static spike hosting and added a Pages deployment workflow scoped to `mobile-pwa/`; production architecture remains open | Owner confirmed “github pages work”; static HTTPS bootstrap enables the actual-iPhone test without becoming a command relay | 2 | User |
| 2026-09-19 | Published the repository and successfully deployed the PWA workflow, but kept hosting unresolved after inherited custom-domain routing made the artifact unreachable | Actions run `35449412793` passed for `93c0155`; `iamads.github.io/pageturner/` redirected to the owner's existing `abhijeet.de` site, which redirected the path to `/de` | 2 | User authorized push/deployment; routing evidence recorded by assistant |
| 2026-09-19 | Restored the expected GitHub Pages project URL after owner removed the old domain and the PWA workflow was redeployed; recorded stale older-site `CNAME` recurrence risk | Pages API now reports no custom domain and enforced HTTPS; workflow run `35450334561` passed; live page and four shell assets return HTTP 200. `iamads/iamads.github.io` still tracks `CNAME` on `master` | 2 | User removed domain; assistant verified and redeployed |
| 2026-09-19 | Recorded a failed desktop browser request from Pages HTTPS to the Kindle HTTP API; subsequent correction below supersedes the initial TLS-required inference | Owner supplied redacted Chrome diagnostics showing a 2 ms fetch failure; independent HTTP probe reached the listener and received 401. Exact browser failure and iPhone behavior remain open | 2 | User supplied diagnostics; assistant verified listener reachability |
| 2026-09-19 | Corrected the blanket Kindle-HTTPS requirement and expanded the options document with simpler alternatives; no architecture selection or phase transition | Chrome LNA documentation explicitly permits permission-gated HTTP private-IP fetches from secure origins. A generic fetch error does not diagnose mixed content; missing CORS/preflight is a known gap. Target-iPhone evidence is still required | 2 | Assistant source correction following owner's request to reconsider alternatives |
| 2026-09-19 | Prepared logging-only plugin update and request-correlation procedure before changing CORS/TLS | Owner requested plugin logs first. Fixed-label diagnostics expose preflight vs command, status and transport lifecycle without secrets; 43 non-optional tests pass, actual device evidence pending | 2 | User for experiment; assistant for local implementation/test evidence |
| 2026-09-19 | Implemented narrowly scoped CORS/preflight in the plugin; no PWA or TLS change and no gate transition | Chrome explicitly reported missing `Access-Control-Allow-Origin` on preflight; owner authorized implementation. OPTIONS cannot turn pages; POST still requires token and reader guards. 47 non-optional tests pass | 2 | User |
| 2026-09-19 | Recorded split browser result: desktop Chrome PWA control succeeds, iPhone Safari/Firefox Focus fails; retained feasibility gate | Owner reports working laptop control after CORS and supplied iPhone Focus diagnostics showing secure context/API availability but a 4 ms HTTP fetch failure. WebKit browsers share the same engine | 2 | User |
| 2026-09-19 | Closed the plain-HTTP PWA transport experiment for tested iPhone WebKit; promoted Kindle HTTPS or an explicit scope alternative as the next decision | Direct phone HTTP navigation returned/logged 401 at 21:54; PWA tap at 21:56 produced no plugin connection before listener stop at 21:57. This proves LAN reachability while isolating PWA blocking before network delivery | 2 | User supplied correlated device/log evidence |
| 2026-09-19 | Confirmed internet availability and non-negotiable PWA wake lock; rejected Shortcut/native/manual-certificate paths; added Tailscale Serve/Funnel as researched candidates without selecting or installing either | Owner requested alternatives and Tailscale research. Official docs plus community KOReader/KUAL projects show promise, but model/kernel/resource/public-exposure questions remain | 2 | User for constraints and research direction; assistant for source findings |
| 2026-09-22 | Made mobile transport platform-adaptive: retain direct IPv4 and private Tailscale endpoint modes in one PWA; add Android direct-HTTP/Home Screen testing as a non-blocking learning objective | Private Serve HTTPS now reaches the Kindle from iPhone, but that iOS-specific workaround must not be generalized without Android evidence. Owner confirmed inline optional ports and non-blocking Android scope | 2; informs later compatibility | User |
| 2026-09-22 | Added and locally implemented QR pairing as the primary setup experiment, with per-start token rotation, verified Serve/local fallback, route text, PWA camera scanning and manual fallback | KOReader v2026.03 has built-in QR rendering; manual endpoint/token transcription is avoidable. Owner approved the lifecycle/payload/UI decisions and implementation; local tests pass but device evidence is pending | 2; no phase transition | User |
| 2026-09-22 | Superseded JSON/PWA-camera pairing with native-camera HTTPS link opening, fragment-only credentials, safe authenticated connection check with inline status/retry, and manual modal; removed decoder/cache assets | Owner reports poor scanner behavior and approved the complete camera-link specification plus implementation. Credentials must not reach GitHub. Native-camera and installed-context device evidence was pending at implementation | 2 setup/measurement; no phase transition | User |
| 2026-09-22 | Recorded deployed camera-link setup as working and replaced experiment-oriented READMEs with current flow and third-party installation/operation guidance | Owner reports “works”; live project app/cache-v4 assets return 200 and contain the current `/connect` flow. Detailed reliability/wake/token lifecycle evidence remains open | 2; no phase transition | User |
