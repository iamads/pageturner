# Bare-word Voice Control Specification

> Status: Implementing — next/back API dispatch wired locally; iPhone validation outstanding
> Last updated: 2026-10-03

## Current action authorization (supersedes detection-only restrictions below)

The user requested connecting `next` and `back` voice detection to Kindle API calls and explicitly retaining the toast messages. The app now keeps `Heard …` toasts and routes `next`/`back` through the existing authenticated sender for both detector choices. `sleep` remains toast-only. Dispatch requires a current listening session, a visible page, a verified connection and no in-flight turn. Existing 800 ms same-command deduplication and no-queue/no-automatic-retry behavior remain. Tests cover dispatch, toast retention, guards and uncertain timeouts; real Kindle/iPhone validation is still outstanding. Service-worker cache v9 refreshes the changed shell.

The original detector-only scope, D-005/D-021/D-023 action restrictions and future-dispatch gate below are historical and superseded by this explicit request. Hidden-page detections are ignored as a dispatch safety guard; broader interruption/resume behavior remains unvalidated.

## Objective
Define an on-device, foreground-only voice-command prototype for Page Turner's PWA using the exact bare English words `next`, `back`, and `sleep`. Separate stable UI/audio/session/command handling from interchangeable model experiments; initially display detections only, with no voice-triggered API calls.

## Scope
### Changes included
- Refine the voice-command requirements and evaluation criteria in light of the keyword-spotting research.
- Define a detector-only validation path before any API dispatch.
- Define two work streams: (A) stable PWA UI, microphone capture, session lifecycle, and command handling; (B) replaceable local detector/model implementations.
### Explicit non-goals
- Prefixed phrases or a required wake word for the initial vocabulary.
- Guaranteed background or locked-screen listening.
- Adding any voice-triggered API dispatch in this prototype.
- Voice-triggered API calls in the initial prototype; `sleep` has no action beyond a detection toast.
- Saving microphone recordings or retaining a timestamped detection log in the UI.
### Unchanged behavior
- Existing authenticated `/next` and `/back` requests, reader guards, wake-lock behavior, and no replay of uncertain turns.
- No Kindle sleep/power change without explicit approval.
### Affected components and dependencies
- Existing `mobile-pwa/` on the owner's iPhone (UI, capture/lifecycle, service-worker asset handling, command toasts), interchangeable sherpa/Vosk detectors, and existing command sender only if dispatch is later authorized. Android is not part of the initial target. The Kindle exposes no `/sleep` route.

## Confirmed decisions
| ID | Decision | Rationale | Consequences | Source |
|---|---|---|---|---|
| D-001 | Initial spoken vocabulary consists only of bare words `next`, `back`, `sleep`; no prefix is required. | User preference. | Test and tune these exact words; do not silently substitute phrases. Supersedes the earlier research preference for `reader next/back` in `pwa-voice-command-spec.md` (P-003), not the historical research. | User, 2026-10-03 |
| D-002 | Foreground-only listening satisfies the product requirement. | User confirmation. | No background or locked-screen promise. Confirms the boundary formerly recorded as assumption A-001 in `pwa-voice-command-spec.md`. | User, 2026-10-03 |
| D-003 | Initially tolerate up to 20 incorrect detections among 100 emitted detections (at least 80% detection precision). | User's initial exploration tolerance. | Evaluate by emitted events, not by audio windows or listening hours; this does not set a recall or false-activations-per-hour target and does not authorize API dispatch. | User clarification, 2026-10-03 |
| D-004 | Initially assume no TV or comparable competing background audio in the intended listening environment. | User-defined initial scope. | Do not treat TV/other-speaker robustness as an initial acceptance gate; record the environmental limitation when reporting results. | User, 2026-10-03 |
| D-005 | Initially display/log `next`, `back`, and `sleep` detections with the detection time, without voice-triggered page-turn requests; add API actions only after confidence is established in a later step. | Avoid acting on experimental misdetections. | UI log/timestamp portion superseded by D-017; no voice-triggered API calls remains in force. | User, 2026-10-03 |
| D-006 | `sleep` is a detectable but actionless command for now. | Functionality will be defined later. | Detection does not stop the microphone, pause listening, or suspend the Kindle. Command detection is shown by a toast per D-017. | User, 2026-10-03 |
| D-007 | Split delivery into a stable PWA/UI/audio/command stream and an experimental, interchangeable model stream. | Permit detector experiments with minimal changes to the application. | Define and test a narrow audio-input/command-event contract; keep app actions outside the model. | User, 2026-10-03 |
| D-008 | Build the first stream inside the existing `mobile-pwa/` and retain its manual controls. | Reuse the current PWA rather than create a parallel prototype. | Add voice as an option without replacing existing Next/Back buttons or changing the Kindle plugin for the detection-only stage. | User, 2026-10-03 |
| D-009 | The model side emits command detections; the PWA owns all actions and future API dispatch. | Keep model experiments independent of app behavior and security. | Model code never receives the endpoint or bearer token and never calls command functions or Kindle endpoints. | User, 2026-10-03 |
| D-010 | Replace the foreground session's `Start wake lock` entry point with `Start listening`: one action requests the wake lock and starts microphone listening; provide a flash notification for this transition. | Single opt-in flow for hands-free use. | Do not require a separate voice-mode start control; design an explicit stop and visible mic state. | User, 2026-10-03 |
| D-011 | Assume wake lock is available in the initial target environment. | User-defined prototype assumption. | Still surface actual failures honestly in testing; availability is not a browser guarantee. | User, 2026-10-03 |
| D-012 | Do not yet decide whether voice resumes automatically after hiding/interruption; discover the right behavior by testing. | User prefers evidence to a premature lifecycle choice. | Leave this decision open; do not claim continuous hidden/background detection. | User, 2026-10-03 |
| D-013 | The “flash notification” is an in-page toast; show it when listening starts and when commands are detected. | User clarified UI behavior. | Timestamped UI log portion superseded by D-017; an OS notification is not required. | User, 2026-10-03 |
| D-014 | Do not spend the current discovery round deciding the hidden-page/interruption behavior or its temporary detection policy. | User does not prioritize this now. | Defer the policy until device tests; do not treat any proposed hidden-state handling as approved. | User, 2026-10-03 |
| D-015 | “Audio collection” means live microphone capture and streaming to the active model only; no saved recordings for training or evaluation. | User clarified the first stream's scope. | Do not add recording, upload, export, persistent audio storage, or an enrollment dataset to the UI stream. | User, 2026-10-03 |
| D-016 | Include a replaceable fake/test detector for exercising the Stream 1 audio/event interface before a real model is ready. | Permit independent development and tests of UI/audio flow. | Test events are simulations, not evidence of recognition quality; keep them unmistakably identified as test-only. | User accepted recommendation, 2026-10-03 |
| D-017 | Replace the timestamped detection log/display with command-detection toasts for the initial UI; no event-history log is needed. | Simplify the prototype UI. | Supersedes the logging/display portions of D-005 and D-013; detection timestamps can remain in the internal event contract for testing but are not displayed as a history. | User, 2026-10-03 |
| D-018 | Keep the fake detector developer/test-only, visibly labeled as simulated; keep a `Stop listening` button that releases the microphone and wake lock. | Avoid confusing simulated events with actual recognition; give user explicit privacy/session control. | No fake recognition in normal mode; start and stop control both session resources together. | User approved recommendation, 2026-10-03 |
| D-019 | Use `sherpa-onnx` streaming keyword spotting as the first real detector for the three bare commands. | Existing configurable offline WASM KWS makes a no-training baseline. | Treat it as an experiment, not a proven accuracy or resource fit; retain the replaceable detector boundary. | User approved recommendation, 2026-10-03 |
| D-020 | Focus initial delivery and device testing on the owner's iPhone PWA only. | Existing project/research scope already targets iPhone; user reiterated it. | Do not expand initial work to Android or ask for redundant platform scope decisions. | User, 2026-10-03 |
| D-021 | Initial Mac test detected about one out of five spoken commands. | User-reported exploratory observation, not a measured device benchmark. | Detector-only status remains; do not enable Kindle actions or assume iPhone recognition will be better. Investigate audio loss separately from model sensitivity. | User, 2026-10-03 |
| D-022 | In the user's Mac test, `next` triggered about 1/5 times, `back` not at all, and `sleep` more often than `next`; deliberately lengthening `next`/`back` improved detection, though `next` still missed. | User-reported qualitative follow-up, not a controlled benchmark. | Alongside a 288-processed/0-dropped sample, this points toward short-utterance sensitivity rather than established audio loss. Do not require lengthened commands or declare threshold tuning sufficient without comparing alternatives. | User, 2026-10-03 |
| D-023 | Add an alternative detector without removing sherpa and permit choosing which one runs from code, not the UI. | Compare approaches using the same voice session after weak short-word detection. | Vosk offline ASR is the second experiment; one constant in `mobile-pwa/detector-config.js` selects either. Keep detection-only toasts, manual controls and app-owned actions. | User, 2026-10-03 |

## Proposed decisions
| ID | Proposal | Alternatives / trade-offs | Recommendation |
|---|---|---|---|
| P-001 | Under confirmed D-009, the PWA owns capture, microphone permissions, framing, timestamps, foreground/stop lifecycle, bounded delivery to a Worker, UI, stale-event/deduplication policy, and the future optional mapping to authenticated API calls. | Letting each model own microphone capture couples UX to model experiments; per-model policy creates inconsistent behavior. | Adopt these detailed responsibilities as the stable stream-1 implementation. |
| P-002 | The detector adapter owns model loading/assets, sample-rate conversion and feature extraction as needed, inference, and candidate recognition. It accepts mono PCM chunks tagged with actual capture sample rate and session identity, and emits only `{command: 'next'|'back'|'sleep', detectedAt, sessionId}` plus status/errors. | Tying the boundary to 16 kHz/log-Mel or to a specific library prevents swapping models; unconstrained model callbacks allow stale/duplicate actions. | Keep the stream contract model-neutral; choose a single timestamp convention and session/epoch check. Timestamp is internal for tests, not a UI history requirement (D-017). |
| P-003 | For an initial test, count each emitted event once: precision = correctly matched command detections / all emitted detections; report wrong-class, duplicate, and unmatched events separately. Also report intended-command recall and unwanted events/hour as diagnostics. | Precision can look good while many intended commands are missed, or while events are too frequent to tolerate; a quiet test does not establish TV/other-speaker performance. | Use the confirmed ≥80% detection precision target in the quiet intended environment; agree on event matching and sample size before action gating. |
| P-004 | Under confirmed D-018, add persistent listening/permission/error state in addition to the start/command toasts. | A toast alone can be missed and does not reveal whether the microphone remains active. | Keep honest visible mic status while preserving the confirmed combined Stop behavior. |
| P-005 | Defer the hidden/interrupted-page policy until device testing, including whether resumption needs a fresh tap. | Browser suspension and permission/lifecycle behavior vary. | No claims of hidden-page recognition and no policy assumed for the initial specification; test before enabling actions. |

## Assumptions and constraints
| ID | Item | Type | Validation needed |
|---|---|---|---|
| A-001 | On-device processing and no required paid service remain desired from the prior research. | Assumption | Confirm if the change in vocabulary also changes deployment constraints. |
| A-002 | `sleep` does not have an action yet, and there is no Kindle sleep API. | Constraint | Future `sleep` behavior requires a new decision; initial detection leaves the session unchanged. |
| A-003 | Both sherpa-onnx (initial default) and Vosk are experimental; the target is the owner's iPhone PWA. Research estimates and desktop synthetic-audio smoke tests are not iPhone measurements. | Constraint | Validate on the target iPhone before claiming performance. |

## Data model
Confirmed: microphone audio is only captured and streamed to the active local detector, not saved as recordings, exported, or uploaded. Vosk may cache its downloaded *model* in browser storage; it does not store microphone recordings. No timestamped detection-history log is required. Proposed: transient bounded mono PCM chunks (`Float32Array`, actual sample rate, capture time/session identifier), detector state, and ephemeral command events. The PWA assigns a new session/epoch ID on each listening start and ignores events after stop or replacement; interruption policy remains deferred. No changes to existing command/token storage are authorized.

## Workflows and interfaces
Confirmed: visible PWA → `Start listening` requests wake lock and microphone access together → stream audio to the active detector → show in-page toasts when listening starts and when `next`/`back`/`sleep` is detected; no timestamped UI log or voice-triggered API action. `Stop listening` releases microphone and wake lock. The fake detector is visibly marked and only available in developer/test mode, not normal recognition. Code-level `ACTIVE_DETECTOR` selects sherpa-onnx (default) or Vosk behind the same PCM/event boundary; both remain detector-only. Existing manual Next/Back controls remain available; interruption/recovery behavior awaits real-device tests.

Proposed stream boundary: PWA audio capture → bounded, timestamped mono PCM chunks → replaceable detector adapter (possibly Worker-backed) → validated command events/status → PWA central command handler (initially toast only; later, separately approved actions). App, not detector, owns microphone permission and command effects. No model-specific frontend assumptions in the interface. The app ignores late events from old sessions and centralizes event deduplication; detector can still use internal smoothing. A model implementation never receives endpoint/token credentials. Future API dispatch for `next`/`back` requires its own gate.

## Edge cases and failure behavior
Initial environment excludes TV/comparable competing audio. Must still handle duplicate detections, microphone denial or revocation, and wake-lock failure (despite the availability assumption). Hidden-tab interruption/recovery policy and stale queued audio handling are deferred to device testing per D-012/D-014; do not promise hidden/background recognition or action dispatch. `sleep` detection has no lifecycle effect. No automatic retry of an uncertain page turn.

## Acceptance criteria
- [x] Define the initial 20% tolerance as 20 incorrect emitted events per 100 detections, in an environment assumed to exclude TV/other competing audio. Event matching and test size remain to be specified.
- [x] Confirm initial scope: detector-only prototype (no voice-triggered API calls); `sleep` only triggers a detection toast.
- [x] Confirm existing `mobile-pwa/` as stream 1, and model events/PWA actions as the ownership boundary.
- [x] Agree that one `Start listening` action starts wake lock plus microphone listening; a flash notification is required (details open).
- [x] Confirm in-page toasts on listening start and command detection, with no timestamped UI history.
- [x] Confirm a replaceable fake/test detector to validate Stream 1 independently of model quality, developer/test-only and visibly simulated.
- [x] Confirm `Stop listening` releases microphone and wake lock.
- [x] Confirm Stream 1 captures and streams audio to the active model only, with no saved recordings.
- [x] Initial PCM/Worker event contract and combined Stop behavior implemented with bounded audio transfer and model-only command events; interruption/recovery behavior deferred to device testing.
- [x] Package pinned sherpa-onnx English WASM/model/keyword assets and verify local Chrome Worker initialization and audio decoding.
- [x] Package a second local detector (Vosk), add a code-only switch, retain sherpa and test shared command-event behavior without enabling API actions.
- [ ] Validate bare-word recognition and resource behavior on target iPhone (no device test or deployment yet).
- [x] Select sherpa-onnx streaming KWS as first experimental real detector (not a production guarantee).
- [ ] Measure observed recall and latency during exploratory iPhone trials, without treating additional targets as a prerequisite to building the initial detector-only prototype.
- [ ] Keep foreground-only limitations and existing API safeguards explicit.

## Open questions
- [ ] Q-001 (deferred): Determine evaluation details after a working iPhone prototype. Recall/latency can be reported without selecting a target now.
- [x] Q-002: Existing `mobile-pwa/` is stream 1; models emit events and the PWA owns actions (D-008/D-009).
- [x] Q-005: One `Start listening` action replaces `Start wake lock` and starts both wake lock and microphone listening; initial tests assume wake lock is available (D-010/D-011).
- [ ] Q-003 (deferred): Other-speaker and quiet-environment negative-audio coverage, if needed after initial device tests.
- [x] Q-007: Include replaceable fake/test detector; no event-history log (D-016/D-017).
- [ ] Q-004 (deferred): Test interruption/resumption on the actual phone; no temporary hidden-page policy approved or requested at this time.
- [x] Q-006: In-page toast on listening start and on command detection (D-013).

## Decision history
| Date | Change |
|---|---|
| 2026-10-03 | Recorded bare-word-only vocabulary and foreground-only product boundary. Captured the stated 20% tolerance without inventing a denominator or approving dispatch; discovery only. |
| 2026-10-03 | User clarified the tolerance as 20 incorrect detections per 100 emitted detections and excluded TV/comparable competing audio from initial conditions. Updated D-003 and added D-004; precision does not by itself establish recall or safety. |
| 2026-10-03 | Confirmed detection-only initial actions, actionless `sleep`, and two independent work streams. Proposed a model-neutral PCM-to-event boundary; application-owned effects avoid changing UI/audio code for each model. No implementation authorized. |
| 2026-10-03 | User confirmed `mobile-pwa/` for stream 1 and event-only models with application-owned actions. Preserved remaining PCM details and lifecycle as proposals; no implementation started. |
| 2026-10-03 | Combined wake lock and microphone under `Start listening`, added flash-notification requirement and initial wake-lock-available assumption. User deferred resume policy pending device tests; no implementation started. |
| 2026-10-03 | Clarified flash as in-page toasts on start and detections. User declined to decide hidden-page safety policy now; deferred it without silently confirming a default. |
| 2026-10-03 | User limited audio collection to live capture and streaming to the active model, excluding saved recordings for training/evaluation. |
| 2026-10-03 | User accepted a fake/test detector and replaced the earlier timestamped detection log with command toasts. D-005/D-013 log requirements are superseded in part by D-017; no audio or event history retained as a UI feature. |
| 2026-10-03 | User approved developer/test-only labeled fake detector and combined `Stop listening` control releasing microphone and wake lock. |
| 2026-10-03 | Selected sherpa-onnx streaming keyword spotting as the first real-detector experiment, not the production default. |
| 2026-10-03 | User reiterated iPhone-only focus and requested no more discovery questions. Deferred ancillary evaluation choices; recall/latency may be measured without setting a gate now. Discovery paused; no implementation approved. |
| 2026-10-03 | User authorized continuing with the concrete Stream 1/Stream 2 work steps. Added PWA capture/Worker boundary, command toasts, localhost-only simulated detector, sherpa bridge, and tests. Initially sherpa WASM/model assets were missing; a wake-lock-only fallback preserves foreground use on failure. |
| 2026-10-03 | User asked for fully packaged local sherpa setup and will manually test on iPhone. Built pinned English INT8 model + single-thread WASM, bundled 3-word BPE configuration and service-worker v6 cache, verified Worker init plus a known-phrase synthetic detection in local Chrome. Synthetic isolated next/back missed, sleep triggered; iPhone/manual validation and deployment still outstanding. |
| 2026-10-03 | User reported roughly 1/5 detections on Mac. Increased the bounded audio queue to ~400 ms, requested a browser-native 16 kHz AudioContext when available, added no-audio-retention processing/drop diagnostics, bumped service-worker cache to v7. This is a pipeline hypothesis, not proof of improved recognition; model limitations remain possible. |
| 2026-10-03 | User supplied per-command Mac observations and longer-articulation contrast; recorded as exploratory evidence (D-022). No model/keyword/action change authorized or claimed to improve recognition. |
| 2026-10-03 | User requested a second detector and code-level switch. Added Vosk 0.0.8 offline WASM browser runtime and its Apache-2.0-labeled small English model as an experimental alternative; sherpa remains default. Both emit identical command events. Local Chrome synthetic next/back/sleep utterances triggered Vosk final exact results, not real-user or iPhone validation. No voice-triggered API calls enabled. |
