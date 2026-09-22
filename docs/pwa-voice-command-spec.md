# PWA Voice Command Research Specification

> Status: Discovery — research only, not implementation approval
> Last updated: 2026-09-21

## Objective
Find the lowest-complication, low-latency way for the iPhone PWA to continuously detect a small set of spoken commands and invoke the corresponding API, preferably using on-phone inference with no cloud transcription round trip.

## Scope
### Changes included
- Research browser audio capture, foreground lifecycle, local keyword spotting, constrained speech recognition, licensing, and target-iPhone feasibility.
- Compare bare commands (`next`, `back`, `sleep`) with prefixed commands (`reader next`, etc.).
- Recommend an architecture and a bounded actual-device validation experiment.
### Explicit non-goals
- Implementing voice control or changing Kindle sleep behavior during research.
- Declaring the current mobile transport or wake-lock gate passed.
### Unchanged behavior
- Existing token authentication, exact-origin CORS, reader guards, and no automatic replay/retry of uncertain turns.
### Affected components and dependencies
- iPhone Safari/installed PWA, microphone permissions, Web Audio, local model/runtime, static hosting, existing command sender, Kindle HTTP API, and HTTPS transport under evaluation.

## Confirmed decisions
| ID | Decision | Rationale | Consequences | Source |
|---|---|---|---|---|
| D-001 | Research continuous recognition of a limited command set with fast action dispatch. | Hands-free page control. | Favor streaming keyword/command detection over general cloud transcription. | User, 2026-09-20 |
| D-002 | Both bare words and a prefix such as `reader` are acceptable research candidates. | Owner requests the easier, more reliable choice with justification. | Compare false activations, latency, training, and deployment effort. | User, 2026-09-20 |
| D-003 | On-phone processing is strongly preferred. | Avoid cloud STT followed by API latency. | Explicitly distinguish local keyword spotting, local STT, and remote STT. | User, 2026-09-20 |
| D-004 | Proceed with research without a blocking interview. | User requests clarification only if needed, then independent research. | Record assumptions instead of inventing implementation decisions. | User, 2026-09-20 |
| D-005 | Do not require a paid service; investigate alternative mechanisms too. | Owner's explicit research refinement. | Prioritize self-hostable open-source keyword spotting/classification with verified model licenses; do not select a metered vendor SDK merely because it has a free tier. | User, 2026-09-21 |

## Proposed decisions
Full findings: [Continuous, free voice-command research](pwa-voice-command-research.md).

| ID | Proposal | Alternatives / trade-offs | Recommendation |
|---|---|---|---|
| P-001 | First try iOS Voice Control activating existing PWA buttons by name. | Least implementation effort and offline recognition, but OS-owned rather than PWA-owned listening. | Preferred first experiment for personal use; not an assumed replacement for the requested embedded recognizer. |
| P-002 | If PWA-owned recognition is required, prototype sherpa-onnx English streaming keyword spotting in WASM. | No phrase retraining or service fees; existing demo needs worker/audio/memory changes and actual iPhone validation. TF.js personal calibration or Vosk grammar are fallback options. | Preferred embedded-engine research candidate, not a proven production choice. |
| P-003 | Detect whole `reader next/back` phrases with one recognizer. | Bare words are faster to say but more likely to occur in conversation; a separate wake-word/command stage adds unnecessary state and model work. | Prefer full prefixed phrases; validate false activations and latency. |
| P-004 | Leave `reader sleep` detection-only until its meaning is approved. | Ending phone listening differs from suspending Kindle or pausing only actions. | Preserve existing power/lifecycle guardrails. |
| P-005 | Validate a detector-only spike before connecting to API dispatch. | Slightly more testing upfront prevents accidental real turns while thresholds/lifecycle are unproven. | Require bounded buffers, stale-event rejection, deduplication and uncertain-result re-arm behavior. |

## Assumptions and constraints
| ID | Item | Type | Validation needed |
|---|---|---|---|
| A-001 | Continuous listening is required during a user-started, visible foreground session, not while iOS locks/suspends the PWA. | Assumption based on existing scope | State the browser boundary prominently; background guarantees would require a different scope. |
| A-002 | Initial commands are English. | Assumption | Use English model support as the initial comparison. |
| A-003 | Exact target iPhone model and OS build are not verified. Existing owner OS report and browser UA differ. | Constraint | Real-device timing, compatibility, thermal, and battery tests. |
| A-004 | `sleep` has no specified semantics and no existing API route. | Constraint | Do not dispatch or add suspend/power behavior without a separate decision. |

## Data model
Proposed: in-memory audio ring buffer and command candidates; no retained audio or transcript by default. Timing/error counters must exclude tokens and raw audio. Exact retention and model-vendor telemetry depend on the selected engine.

## Workflows and interfaces
Proposed: tap Start → microphone permission and audio/model startup → streaming local detection → confidence/duplicate/state guards → one authenticated command request. Explicit Stop releases microphone and wake lock. No cloud audio upload is assumed.

## Edge cases and failure behavior
Research must address conversation/TV false triggers, overlapping detections, interruptions, model loading failures, microphone revocation, uncertain HTTP results, service-worker limits, and wake-lock release.

## Acceptance criteria
- [x] Evidence-based comparison with primary-source links, compatibility and license caveats.
- [x] Clear recommendation for bare versus prefixed commands.
- [x] Distinguish documented capability from actual-device evidence and proposed targets.
- [x] Concrete latency, false-activation, command-accuracy, and session-lifecycle test plan.
- [x] No claim of guaranteed background/locked-screen PWA listening.

These checkboxes mark research deliverables only, not successful voice-control trials or implementation approval.

## Open questions
Deferred, nonblocking for research: target iPhone hardware/build; meaning of `sleep`; acceptance of OS Voice Control versus PWA-owned listening; accented/quiet speech performance; eventual background requirement, if changed. Paid-service dependence is excluded by D-005. No further questions were asked during research, as requested.

## Decision history
| Date | Change |
|---|---|
| 2026-09-20 | Created research scope from owner's continuous, low-latency local voice-command request. No implementation or phase transition authorized. |
| 2026-09-21 | Owner explicitly excluded paid services and requested other mechanisms. Expanded comparison to OS Voice Control and free local KWS/classifier/grammar approaches. |
| 2026-09-21 | Completed primary-source research and pinned source review; recommended an OS Voice Control trial for least effort, or a sherpa-onnx complete-phrase detector spike for PWA-owned recognition. No on-device audio benchmark or API implementation was performed. |
