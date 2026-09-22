# Camera Link Pairing Specification

> Status: Implemented — deployed; owner reports the camera-link setup works
> Last updated: 2026-09-22

## Objective
Replace in-PWA QR scanning with a KOReader-generated website link that ordinary phone cameras can open, automatically configure Kindle credentials, and show inline connection success or failure.

## Scope
### Changes included
- Generate QR content linking to `https://iamads.github.io/pageturner/` with encoded Kindle endpoint and bearer token.
- Extract connection information automatically on website arrival.
- Show connection success/failure inline, not in a popup.
- Remove PWA QR scanning responsibilities.
- Move manual Kindle endpoint/token entry into a modal; connection results remain inline on the main page.
### Explicit non-goals
- No automatic page turns during pairing.
- Proposed: no public Kindle exposure or changes to the transport strategy.
### Unchanged behavior
- Proposed: manual setup fallback, session-token lifecycle, Next/Back and wake-lock behavior.
### Affected components and dependencies
- KOReader pairing payload; PWA startup, scanner UI/assets, service worker; connection-verification API; tests and documentation.

## Confirmed decisions
| ID | Decision | Rationale | Consequences | Source |
|---|---|---|---|---|
| D-001 | QR must encode a link to `https://iamads.github.io/pageturner/` carrying Kindle URL and bearer token. | Enable ordinary phone-camera scanning. | Replace existing JSON QR payload. | User, 2026-09-22 |
| D-002 | Website automatically extracts credentials and displays connection success/failure inline. | Remove manual pairing steps and popups. | Actual authenticated connectivity must be checked. | User, 2026-09-22 |
| D-003 | PWA does not handle QR scanning. | Existing scanner does not work well. | Remove camera/decoder integration. | User, 2026-09-22 |
| D-004 | Put encoded endpoint/token in the URL fragment, clear it immediately after extraction, and retain credentials only in memory. | User specifically prefers not to send credentials to GitHub. | Reload requires rescanning or manual setup; do not log or persist credentials. | User confirmation of choice 1, 2026-09-22 |
| D-005 | Add an authenticated, non-mutating connection check; show inline success/failure with a retry button. | Prove connectivity without turning pages. | Extend Kindle API and narrowly scoped CORS. | User confirmation of choice 2, 2026-09-22 |
| D-006 | Keep manual endpoint/token fallback, presented in a modal. | User requested modal entry. | Input modal is allowed; connection-result popups are not. | User confirmation/modification of choice 3, 2026-09-22 |
| D-007 | Approve the complete final checklist and specification defaults: P-003 preservation boundaries, P-004 timeout/retry/control gating, P-005 modal behavior, validation/error/API defaults, A-001/A-002 constraints, and coordinated delivery/testing/rollback. | User approved final review. | All previously proposed defaults below are now confirmed; original proposal wording is retained as decision history. Implementation had not started at approval. | User: “approved”, following final checklist, 2026-09-22 |

## Proposed decisions

All remaining proposals and defaults were confirmed by D-007. Original wording is retained for traceability.
| ID | Proposal | Alternatives / trade-offs | Recommendation |
|---|---|---|---|
| P-001 | Fragment credentials and immediate removal. | Original link remains visible to camera/browser software; history replacement cannot erase camera history. | Confirmed as D-004. |
| P-002 | Safe authenticated connection check and retry. | A page-turn request is not a safe connectivity probe. | Confirmed as D-005; timeout details in P-004. |
| P-003 | Retain manual fallback, session-token rotation, endpoint selection, Next/Back and wake lock; remove scanner UI, decoder assets and cache entries. | Manual fallback confirmed as D-006 with modal entry. | Preserve other existing behavior. |
| P-004 | Use a three-second check timeout, no automatic retries, and disable page-turn buttons until verification succeeds. | A successful check proves current connectivity/authentication, not future reachability or reader readiness. | Inline actionable failure; explicit Retry connection action. |
| P-005 | Modal has masked token entry, accessible labels/focus, Connect and Cancel. Connect closes the modal, clears the token field, and checks connectivity; Cancel clears entered token and leaves the current connection unchanged. | Keeps status outside the modal and prevents accidental connection replacement on cancellation. | Apply the same validation/check to manual and link input. |

## Assumptions and constraints
| ID | Item | Type | Validation needed |
|---|---|---|---|
| A-001 | Native camera opens a browser; installed-PWA handoff is controlled by the phone OS and cannot be guaranteed. | Constraint | Accepted in D-007; actual context requires device testing. |
| A-002 | A readable QR does not guarantee network reachability: HTTPS/mixed-content and private Tailscale requirements remain. | Constraint | Accepted in D-007; transport requirements preserved. |

## Data model
Confirmed: URL-encoded endpoint/token in the link fragment; credentials stay in app memory, with no persistent storage or diagnostic logging. Proposed: include a pairing version, validate supported version, unique fields, endpoint and token before any fetch. Clear the fragment even when invalid. Manual token input is masked and cleared after submission/cancellation. Existing per-manual-start token rotation remains proposed unchanged.

## Workflows and interfaces
Start KOReader listener → display URL QR → scan in native camera → open website → extract/clear fragment → validate credentials → authenticated non-mutating check → inline result.

Manual fallback: open manual-connection modal → enter Kindle endpoint/token → Connect → close modal and show checking/result inline on the main page. Cancel preserves the active connection.

Proposed check contract: bodyless authenticated `POST /connect`, HTTP 204 on success; existing exact Pages-origin CORS rules extended only to this route. No page turn, no queue mutation, and no requirement to close the Kindle QR/menu for the check. Existing command reader guards remain unchanged.

## Edge cases and failure behavior
Proposed defaults for final confirmation:
- Missing/malformed/duplicate/unsupported link fields: clear fragment, show a fixed token-safe inline validation error, send no request.
- Plain website visit: show not connected with manual-entry instructions.
- Stale token: inline authentication failure; ask user to scan the current Kindle link.
- Network failure/timeout: inline failure and explicit Retry connection; never automatically retry or turn pages.
- Keep valid credentials in memory for retry; ignore superseded check responses.
- Reload/reopen requires scanning or manual entry again.
- Connection checks work while the Kindle QR/menu is open; page turns still require existing reader guards.
- Modal supports keyboard dismissal/focus restoration; results are accessible inline status messages.

## Acceptance criteria
Checked items have implementation/local-test evidence only, not physical-device acceptance.
- [x] Native camera recognizes the QR as a website link on the owner's tested setup (owner: “works”; detailed device matrix not supplied).
- [x] Valid link configures endpoint/token automatically and checks authenticated connectivity without turning a page.
- [x] Success/failure is inline, never a popup.
- [x] PWA contains no camera/QR scanning integration.
- [x] Credentials are not sent to hosting via URL query, logged or persisted; fragment removal precedes fetch. Manual form uses `method="dialog"`, preventing default GET submission to hosting even without its JS handler.
- [ ] Manual input uses an accessible modal; both connection paths show results on the main page. Native dialog/labels/focus restoration implemented and controller-tested; actual browser accessibility remains to verify.
- [x] Invalid links send no request; stale token and timeout fail safely; retry never turns a page.
- [x] Current deployed pairing/connection setup works on the owner's Kindle/phone environment. The concise report does not separately establish every menu/pending-turn scenario.
- [x] Existing command/token behavior is preserved in regression tests.
- [x] Automated payload, validation, API/auth/CORS and UI-flow coverage passes; physical native-camera scan remains a device acceptance test.

## Implementation and validation
- URL contract: `https://iamads.github.io/pageturner/#version=1&endpoint=<percent-encoded endpoint>&token=<token>`.
- `/connect` reuses the strict HTTP authentication/parser and returns a non-navigation 204 before `main.lua`'s existing reader/queue guards. `/next` and `/back` retain their guards.
- Removed camera UI, camera diagnostics and vendored decoder; replaced cache v3 with v4. Existing v3 clients should load the site to update the worker, then reload to the new manual-modal shell before scanning.
- Local tests: **87 passed** — 39 Lua plugin/API/pairing, 9 Lua network, 6 Python client and 33 JS parser/controller/cache/wake-lock tests. Three optional real-socket tests skipped; local LuaSocket is unavailable. JS syntax and `git diff --check` pass.
- JS app tests use DOM/fetch doubles; they do not validate native modal behavior, actual QR recognition, phone security policy or wake-lock behavior.
- Commit `68e028e` is on `main`; live HTTP checks confirm cache-v4 app assets and `/connect` controller code at https://iamads.github.io/pageturner/. The owner installed the updated plugin and reports the setup works. No phase transition is inferred; detailed stale-token, wake-lock, interruption, accessibility, Android and long-session evidence remains pending.

## Delivery and rollback
Proposed: update Kindle plugin and PWA together, invalidate obsolete scanner service-worker caches, remove decoder assets, and update setup documentation plus current roadmap/handoff references while preserving historical decisions. Old JSON QR payloads require the updated plugin. Run existing regression suites plus new tests; explicitly distinguish automated results from phone/Kindle validation. Rollback requires reverting both plugin and PWA and invalidating the PWA cache; Tailscale registration/state remains untouched.

## Open questions
- [x] Q-001 Confirm fragment credentials and memory-only behavior: D-004.
- [x] Q-002 Confirm safe authenticated connection-check API and retry behavior: D-005.
- [x] Q-003 Confirm manual fallback: D-006, in a modal.
- [x] Q-004 User approved the complete final checklist, including preservation boundaries, browser/transport constraints, error/modal/API defaults and delivery/acceptance expectations.

## Decision history
| Date | Change |
|---|---|
| 2026-09-22 | Recorded requested strategy and proposed security/connectivity decisions; implementation not started. |
| 2026-09-22 | User approved fragment/memory-only credentials and safe connection check with inline retry; retained manual fallback with new modal-entry requirement. Added implementation defaults for final review; no code implemented. |
| 2026-09-22 | User approved the complete final checklist. Confirmed remaining defaults and constraints as D-007; specification marked Approved. Awaiting choice of execution plan or implementation. |
| 2026-09-22 | User requested implementation. Implemented URL QR, safe authenticated check, fragment consumption, inline results/retry, manual modal and scanner removal; 87 local tests pass. Updated docs, roadmap and CI while preserving prior handoff edits as historical evidence. Deployment and device acceptance were pending at that point. |
| 2026-09-22 | Owner reports “works” after installing the updated plugin. Verified the current cache-v4 app and `/connect` controller are live at the project URL. Marked implementation deployed/working while retaining unreported detailed reliability and lifecycle checks. |
