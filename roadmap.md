# Product Roadmap

> Status: Discovery
> Current phase: Kindle remote-control feasibility — implementation authorized; roadmap discovery paused
> Last updated: 2026-09-18

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
- Confirmed: Build the minimal first version now; pause broader roadmap refinement. Focus exclusively on programmatic next/back, shared-token protection, and diagnostic timing.

### Target users and core job
- Confirmed: The owner will test laptop-to-Kindle page turning on their own Kindle first.
- Confirmed: Personal use while reading in bed; phone voice control should remove the need to touch the Kindle to turn pages.
- Confirmed: Possible later plugin distribution, not a current commitment or broader-user validation requirement.

### Product principles
- Confirmed: Establish device-level control before adding voice input.
- Proposed: Reuse KOReader's supported events and networking facilities where practical.
- Confirmed: Everything outside the added remote next/back capability should continue working as it already does. Preserve existing KOReader settings, local controls, navigation behavior, and normal lifecycle behavior.
- Proposed implementation guardrail: Keep remote input from blocking reading or destabilizing KOReader; reuse normal reader navigation rather than modifying it.
- Proposed: Start on a trusted local network without public internet exposure.

### Explicit non-goals
- Confirmed for the first version: Phone voice recognition.
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
- Unknown: Phone operating system, offline/privacy requirements, and background listening needs.

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

### Critical uncertainties
| ID | Uncertainty / hypothesis | Why it matters | How it will be tested | Status |
|---|---|---|---|---|
| H1 | A custom plugin can be installed and run on the owner's Kindle | Prerequisite for all later work | Inspect device setup and load a minimal plugin | Owner reports MVP works; plugin menu/startup observed by owner |
| H2 | KOReader can accept laptop HTTP requests without blocking the UI | Determines initial transport | Inspect upstream networking and run an on-device spike | HTTP reachability observed; responsiveness guardrails need detailed evidence |
| H3 | Next/back can safely invoke reader page navigation | Requests alone do not prove useful control | Inspect navigation events; verify visible page changes in both directions | Owner reports MVP works; exact 20-turn/regression results unreported |
| H4 | Wireless connectivity remains usable during real reading | Sleep/power behavior may undermine practical use | Reading-session and reconnect tests | Unknown |
| H5 | Voice commands offer repeated value with acceptable recognition errors | Determines whether phone work is justified | Owner use-case interview, then phone prototype and reading trials | Unknown |

## Roadmap overview
| Phase | Purpose | Exit outcome | Confidence | State |
|---|---|---|---|---|
| 1. Kindle remote-control feasibility | Prove installation, request handling, and actual page navigation | Owner demonstrates both directions from a laptop without breaking local reading | Medium; owner reports MVP success | In-device use reported; gate evidence incomplete; usability refinement |
| 2. Usable laptop-controlled reading | Establish reliability and operational limits | Repeated reading sessions meet agreed reliability, latency, and recovery guardrails | Low | Proposed next |
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

## Next phase: Usable laptop-controlled reading
### Purpose and strategic question
Does the control path remain dependable during actual reading, rather than only a short demonstration?

### Target users and use case
Proposed: Owner reading in bed on their Kindle while using laptop-issued commands over the shared Wi-Fi, as a control-path validation step rather than the final hands-free experience.

### Hypotheses
H4; requests can be handled without confusing duplicates, unexpected page movement, or disruptive recovery steps.

### Bets and experiments
- Run normal reading sessions, including quiet periods, Wi-Fi interruption, and KOReader restart.
- Establish expected behavior for sleeping devices, closed books, rapid commands, and failed requests.
- Add only the lifecycle, configuration, access control, and diagnostics needed for dependable use.

### Measurement and instrumentation
Record attempted commands, correct/incorrect visible navigation, connection failures, manual recovery, and reading disruption alongside implemented acknowledgement RTT logs. Optional battery observations may inform later decisions; do not add always-on power management or make battery research a v1 blocker.

### Required outcomes and guardrails
- P2-O1 (confirmed): Owner completes two 30-minute reading sessions with no missed/duplicate turns or disruption to normal KOReader behavior. Record command counts and timing; no numeric latency gate for now.
- P2-O2 (proposed): Recovery from tested interruptions follows documented behavior without unexplained extra page turns or loss of reading position.
- P2-O3: Confirmed guardrail: Existing KOReader behavior remains unchanged outside the added remote controls. Proposed acceptance evidence: Repeat baseline local-reading/lifecycle checks during session trials; power cost and network exposure must be explicitly accepted.
- Confirmed: Do not change sleep settings or other unrelated behavior. Normal device sleep may make requests unavailable; waking remotely or preventing sleep is out of scope.
- Proposed: Record normal-session battery observations if useful; do not add power-management features or block v1 on a battery study.

### Exit gate
Project owner reviews two 30-minute session results against P2-O1–O3 before phone integration; advancement still requires explicit acceptance of evidence.

### Pass, mixed, and fail decisions
- Pass: Proceed to a minimal phone voice experiment if the hands-free use case is confirmed.
- Mixed: Resolve the failure mode or narrow supported conditions before adding voice.
- Fail: Revisit transport, power assumptions, or whether the use case is practical.

### Dependencies and constraints
Requires phase 1 evidence. Same-Wi-Fi and simple shared-token access control are confirmed. Owner may keep the device awake manually for testing; the plugin must not change sleep/power settings. Timing is diagnostic rather than a numeric gate.

### Non-goals
Proposed: Cloud services, polished phone application, broad recruitment, and expanded commands.

## Later direction
### Phone voice proof of value
- Directional purpose: Let the owner say next/back on a phone and continue reading without touching the Kindle.
- Entry trigger: Reliable control path accepted and hands-free reading situation confirmed.
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
- Broader roadmap discovery remains paused at the user's request; no phase has advanced and the full roadmap has not been declared Active.

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
- [x] First functional demonstration: Install plugin; 20 alternating commands, each producing one correct turn; touch navigation still works.
- [x] Latency boundary: <100 ms for command delivery to Kindle, not completed e-ink refresh.
- [x] Log round-trip timing; defer latency optimization and do not impose a <100 ms first-version gate.
- [x] Next reliability trial: Two 30-minute sessions, no missed/duplicate turns or normal-behavior disruption.
- [ ] Time/resource constraints and acceptable manual setup?
- [ ] Phone platform, privacy/offline requirements, and background listening expectations?
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
