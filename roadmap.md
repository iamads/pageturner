# Product Roadmap

> Status: Discovery
> Current phase: Kindle remote-control feasibility — acceptance evidence open; next-phase mobile PWA discovery approved
> Last updated: 2026-09-19

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
- Confirmed: Development for this next phase is isolated on `feat/mobile-pwa`. This update creates the roadmap revision and [handoff](docs/mobile-pwa-handoff.md) only; no PWA implementation has begun.

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
- Confirmed: Phone + Kindle only for mobile operation; no running laptop bridge.
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
- Unknown: PWA hosting/bootstrap and offline-install requirements, acceptable certificate/trust setup, token pairing/storage UX, and privacy/background-listening requirements for the later voice phase.

## Strategic context
### Evidence already available
- At discovery start, the project directory was empty. A minimal plugin, laptop client, install instructions, and local tests are now implemented. Owner now reports “Mvp works”; detailed gate results remain unreported.
- 2026-09-18: The Kindle listener responded to an unauthenticated laptop probe with the expected HTTP 401. This verifies reachability/authentication rejection, not a page turn.
- Owner requests easier menu access and visible Wi-Fi name/IP/port after startup. Implemented as first entry in the default Tools menu and a fresh, read-only connection-details popup; on-device UI verification is pending. This is an in-scope usability refinement, not a strategy or phase-gate change.
- Implementation: `pageturner.koplugin/`, `tools/pageturner.py`, and `README.md`. HTTP exposes only authenticated bodyless POST next/back, with diagnostic timing and no sleep/Wi-Fi/settings changes.
- Source compatibility was checked against **v2026.03**, not only moving master. Findings and references: [KOReader research](docs/koreader-research.md).
- Local validation: 21 Lua plugin tests, 9 Lua network tests, 6 Python client tests, and 3 real LuaSocket transport integration tests passed. A smoke check using the actual v2026.03 menu sorter/order also confirmed first Tools placement. Mocks/source checks do not replace actual Kindle UI or power-behavior tests.
- Owner reports KOReader 2026.03 already running on their Kindle and confirms same-Wi-Fi testing with the device awake.
- Owner-reported MVP success supports initial HTTP/navigation feasibility. Exact command count, latency distribution, and regression/session results are still unknown.
- Upstream source inspected on 2026-09-18 (moving `master`, not the owner's installed version): [HTTP inspector](https://github.com/koreader/koreader/blob/master/plugins/httpinspector.koplugin/main.lua) already runs an HTTP listener using `ui/message/simpletcpserver`, registers it with the UI manager, adds/removes Kindle firewall rules, and exposes event dispatch over HTTP. This is strong implementation precedent, not an on-device test.
- [Auto-turn plugin](https://github.com/koreader/koreader/blob/master/plugins/autoturn.koplugin/main.lua) invokes `self.ui:handleEvent(Event:new("GotoViewRel", 1))` through its default distance. [Dispatcher](https://github.com/koreader/koreader/blob/master/frontend/dispatcher.lua) exposes this event as “Turn pages” with signed numeric distances. Proposed next/back mapping: +1/-1; verify behavior in the owner's reading mode and book format.
- Proposed: Use HTTP inspector only as a short, trusted-network diagnostic if available, then reuse the relevant patterns in a narrow next/back plugin. Its arbitrary event/method inspection surface is broader than this product needs.

- PWA source research: [Screen Wake Lock API](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API) requires a secure context and an active/visible document; the OS can deny/release it. [WebKit Safari 18.4 notes](https://webkit.org/blog/16574/webkit-features-in-safari-18-4/) document Home Screen web-app wake-lock support. This is not execution evidence for the owner's reported iOS 26.6.
- Browser transport risk: Current Kindle API is plain HTTP and has no CORS/OPTIONS handling. [Mixed-content rules](https://developer.mozilla.org/en-US/docs/Web/Security/Mixed_content) normally block HTTPS-page fetches to HTTP endpoints; CORS alone is not a remedy. Exact local-network/security behavior must be verified on the target iPhone.
- 2026-09-19: A framework-free diagnostic PWA shell now exists in `mobile-pwa/`. It records secure-context/install/wake-lock state, accepts IP/port/token in memory, sends commands once with no replay, and never service-worker-queues command requests. Local syntax/static-serving checks pass. After the owner removed the old account-level Pages domain and the workflow was redeployed, `https://iamads.github.io/pageturner/` and all shell assets returned HTTP 200 over HTTPS. The older user-site repository still tracks `CNAME` with `abhijeet.de` on its `master` Pages source branch, creating recurrence risk on a future legacy rebuild. No target-iPhone test has occurred, so H6/H7 remain unknown.

### Critical uncertainties
| ID | Uncertainty / hypothesis | Why it matters | How it will be tested | Status |
|---|---|---|---|---|
| H1 | A custom plugin can be installed and run on the owner's Kindle | Prerequisite for all later work | Inspect device setup and load a minimal plugin | Owner reports MVP works; plugin menu/startup observed by owner |
| H2 | KOReader can accept laptop HTTP requests without blocking the UI | Determines initial transport | Inspect upstream networking and run an on-device spike | HTTP reachability observed; responsiveness guardrails need detailed evidence |
| H3 | Next/back can safely invoke reader page navigation | Requests alone do not prove useful control | Inspect navigation events; verify visible page changes in both directions | Owner reports MVP works; exact 20-turn/regression results unreported |
| H4 | Wireless connectivity remains usable during real reading | Sleep/power behavior may undermine practical use | Reading-session and reconnect tests | Unknown |
| H5 | Voice commands offer repeated value with acceptable recognition errors | Determines whether voice input is justified after button control | Owner use-case interview, then voice prototype and reading trials | Unknown; deferred until after mobile button control |
| H6 | A secure-context PWA can directly control the Kindle without a laptop/relay | Determines viable mobile architecture | On-device origin/TLS/local-network/CORS experiment, including installed Home Screen mode | Unknown; first mobile experiment |
| H7 | The visible PWA can prevent auto-lock and safely recover after visibility changes | Required for the mobile reading experience | Actual iPhone idle, background/return, and wake-lock denial/release tests | API precedent; target device untested |
| H8 | The owner can pair/authenticate without leaking the token or excessive setup | A browser cannot read the laptop's token file automatically | Test explicit token entry/pairing and accepted storage/trust setup | Unknown; authentication remains required |

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
Can the owner control their Kindle directly from a usable iPhone PWA, keep the phone screen awake while that PWA is visible, and rely on the controls throughout reading in bed—without a running laptop?

Confirmed revision on 2026-09-19: Replaces **Usable laptop-controlled reading** with mobile button control plus reliability validation. Retains the two 30-minute sessions and no-regression guardrails; moves them onto the phone. This is a sequencing revision, not a declaration that phase 1 passed.

### Target users and use case
Confirmed: Owner, iPhone on reported iOS 26.6, and Kindle running KOReader 2026.03 on the same Wi-Fi. Enter Kindle IP/port and supply the existing authentication token, then use Next/Back buttons while the PWA remains visible. No laptop is required during use.

### Hypotheses
H6 and H7 are the first risks to resolve; H8 governs pairing/setup. H4 and reliable one-request/one-turn behavior remain relevant. Voice value (H5) is deferred, not a prerequisite for button control.

### Bets and experiments
1. **Connectivity/wake-lock spike first (confirmed sequencing).** On the actual iPhone, record OS/build, Safari versus installed Home Screen context, secure-context status, frontend origin, Kindle endpoint, local-network permissions, and any TLS/mixed-content/CORS errors. Prove authenticated next/back and wake lock together in the intended deployment; do not treat an HTTPS wake-lock demo and an unrelated HTTP control page as a combined success.
2. Investigate a trusted HTTPS endpoint on the Kindle or another demonstrated direct browser-to-Kindle design that satisfies secure-context requirements. This is a candidate, not a selected architecture. Evaluate certificate trust, hostname/IP matching, renewal, and DHCP changes before choosing. No running laptop bridge or command relay satisfies the confirmed phone+Kindle requirement.
3. If using distinct origins, provide narrowly scoped preflight/CORS behavior while keeping actual commands token-authenticated. Do not remove authentication, use opaque `no-cors` requests, or assume local-network permission bypasses mixed-content rules.
4. Once the spike passes and setup trade-offs are accepted, build a minimal mobile UI: endpoint/authentication setup, large Next/Back controls, honest connection/error feedback, and visible wake-lock state. Installation/bootstrap, offline shell behavior, and token persistence are still design decisions.
5. Acquire a screen wake lock for the visible control session, observe release/denial, and attempt reacquisition on return to visibility as allowed by the platform. Provide an explicit end/disable action and release when appropriate; no background-execution guarantee, global Auto-Lock changes, or audio/video keep-alive tricks.
6. Run the carried-over two 30-minute reading sessions on the phone, plus interruption cases: wrong token, unreachable/sleeping Kindle, open Kindle menu, changed IP, failed request, app background/return, and phone manual lock. Never replay uncertain page-turn commands after recovery.

### Measurement and instrumentation
- Capture the exact origin/endpoint/security context and browser errors, plus Home Screen install/launch evidence on the target phone. Keep tokens out of logs, URLs, screenshots, and source control.
- Record button taps, HTTP acknowledgements, corresponding observed page changes, RTT, errors, and recovery actions; HTTP 202 still means acceptance, not completed rendering.
- Record wake-lock acquisition/release/denial and visibility changes. Establish the phone's existing Auto-Lock interval without changing it, then observe an idle foreground interval longer than that timeout; record elapsed time and whether the screen stayed awake.
- Session evidence: Duration, command counts, missed/duplicate/incorrect turns, normal KOReader behavior, interruptions, and manual intervention. Keep timing diagnostic; no new <100 ms gate.

### Required outcomes and guardrails
- P2-O1 (confirmed, revised platform): Owner completes **two 30-minute phone-controlled reading sessions** with no missed/duplicate turns or disruption to normal KOReader behavior. Record command counts and timing.
- P2-O2 (retained proposed operational criterion): Recovery from tested interruptions is understandable, with no replayed/extra page turns or lost reading position. Wake-lock denial/release is shown honestly, not as an active lock.
- P2-O3 (confirmed): Existing Kindle/KOReader behavior and authentication remain intact. No Kindle sleep-setting changes, remote wake, automatic Wi-Fi changes, or laptop dependency. Regression and security checks remain required evidence; precise battery budget is not a blocker.
- P2-O4 (confirmed capability; proposed measurement): Owner can install/launch the PWA on the target iPhone, supply IP/port/token, and produce one correct next and back turn using a documented direct connection with no running laptop. Repeat after relaunch and verify unauthorized requests do not turn pages. Setup/certificate steps must be explicitly accepted before broader UI work.
- P2-O5 (confirmed capability; proposed measurement): While the installed PWA is visible and the OS grants a wake lock, the phone stays awake through an idle interval longer than its configured Auto-Lock timeout, including idle periods in the session trials. Background/manual lock and OS revocation may end the lock; return/reacquisition or an actionable unavailable state must be observed. No promise of unrestricted background operation.

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
- Confirmed target: Owner-reported iOS 26.6, KOReader 2026.03, same Wi-Fi, phone+Kindle-only operation, existing bearer token, foreground-only phone wake lock.
- Current API is HTTP-only, bodyless POST next/back, with no TLS, static hosting, health endpoint, CORS, or OPTIONS support. A static PWA alone cannot be assumed to connect successfully.
- Confirmed for the spike: GitHub Pages hosts the static PWA shell at `https://iamads.github.io/pageturner/`; it is not a command relay and contains no token. Live page and shell-asset HTTP checks pass. The stale `CNAME` in the older user-site repository should be removed separately if the old domain must stay detached.
- Unknown: Post-install offline requirements, Kindle-side certificate provisioning/trust acceptance, production frontend architecture, token pairing/storage, and precise iOS local-network behavior. Investigate before committing implementation architecture.
- Work isolated on `feat/mobile-pwa`; handoff: [Mobile PWA handoff](docs/mobile-pwa-handoff.md). The current change is documentation only.

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
- 2026-09-19: Added the minimal `mobile-pwa/` feasibility harness before choosing a production architecture. It includes install metadata/offline shell caching, direct endpoint configuration, one-shot Next/Back requests, foreground wake-lock lifecycle controls, and token-redacted diagnostics. GitHub Pages is now live at the expected `github.io` project URL after custom-domain removal and redeployment. No Kindle API/TLS/CORS behavior changed; actual-iPhone combined connectivity/wake evidence remains the next checkpoint.
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
- [ ] Verify exact iPhone OS/build, installed-PWA behavior, and local-network/security restrictions during the spike.
- [ ] Choose a direct secure-context connection design; agree acceptable certificate/hostname/trust setup before implementation commitment.
- [x] Static spike hosting/bootstrap: GitHub Pages is live at `https://iamads.github.io/pageturner/`; remove the stale older-site `CNAME` separately to avoid recurrence.
- [ ] Decide production/offline shell behavior and token entry/storage/pairing UX after the spike.
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
