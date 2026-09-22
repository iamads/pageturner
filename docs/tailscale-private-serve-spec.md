# Private Tailscale Serve Spike Specification

> Status: Implementing
> Last updated: 2026-09-21

## Objective
Validate whether the installed iPhone PWA can send authenticated next/back commands over a private Tailscale Serve HTTPS endpoint to Page Turner on the target Kindle while retaining foreground wake lock.

## Scope
### Changes included
- A reversible private Tailscale Serve experiment.
- Kindle compatibility checks and isolated persistent node registration.
- Serve proxying to the existing Page Turner listener on port 8088.
- Tailscale on the iPhone and PWA support for a private HTTPS hostname on standard port 443.
- Functional, security, resource, sleep/resume, and rollback validation.

### Explicit non-goals
- Enabling Tailscale Funnel or any other public endpoint.
- Selecting Serve as the permanent production transport before spike results exist.
- Weakening bearer-token authentication or broadening the allowed browser origin.
- Enabling Tailscale SSH, exit-node use, subnet routes, or a global KOReader proxy.
- Changing Kindle sleep behavior or retrying uncertain page turns.

### Unchanged behavior
- Page Turner remains manually enabled per open book.
- Only bodyless authenticated `POST /next` and `POST /back` can turn pages.
- The PWA does not persist or log the bearer token and does not retry commands.
- Normal KOReader navigation, suspend, and lifecycle behavior remain intact.

### Affected components and dependencies
- Target Kindle, KOReader, Page Turner plugin, Tailscale daemon/CLI, iPhone Tailscale app, tailnet access policy, private DNS/TLS endpoint, and `mobile-pwa`.
- GitHub Pages remains the PWA host at `https://iamads.github.io/pageturner/`.

## Confirmed decisions
| ID | Decision | Rationale | Consequences | Source |
|---|---|---|---|---|
| D-001 | Superseded by D-016: evaluate Tailscale Funnel next. | The owner initially requested a Funnel trial. | Preserved as history; no Funnel endpoint will be enabled under the current decision. | User, 2026-09-20 |
| D-002 | Preserve the PWA and foreground wake-lock approach. | Existing phase constraints require both. | The PWA needs hostname/443 support rather than replacement by a native client. | Existing roadmap, 2026-09-20 |
| D-003 | Target a Kindle Paperwhite 3 with KOReader and KUAL installed. | This is the owner's available reader. | Compatibility work must account for an older Kindle platform; KOReader/KUAL provide possible packaging and script-launch paths. | User, 2026-09-20 |
| D-004 | Superseded by D-016: temporary public exposure was acceptable for the abandoned Funnel test. | Funnel was initially being evaluated. | Preserved as history; current scope prohibits public exposure. | User, 2026-09-20 |
| D-005 | The owner will create a Tailscale account/tailnet. | No existing tailnet is available. | Account creation and Funnel policy authorization are prerequisites. | User, 2026-09-20 |
| D-006 | Files can be transferred to the Kindle manually. | This is the currently confirmed deployment method. | Installation instructions cannot assume SSH/SCP. | User, 2026-09-20 |
| D-007 | Collect the minimal read-only compatibility diagnostics through a KUAL-launched script that writes an output file. | The owner approved the checks and has not configured SSH. | The first device change is limited to adding/removing a diagnostic extension; no daemon, login, or public endpoint is involved. | User, 2026-09-20 |
| D-008 | The target Kindle firmware is 5.12.3. | Reported from Device Info by the owner. | Binary compatibility must be validated against this older firmware's actual kernel and CPU. | User, 2026-09-20 |
| D-009 | Proceed now with only the removable KUAL compatibility diagnostic. | The owner explicitly approved creating it after the installation flow was clarified. | No Tailscale binary, account credential, network setting, or Funnel endpoint is included at this step. | User, 2026-09-20 |
| D-010 | Device inventory: Linux 3.0.35-lab126, 32-bit ARMv7/i.MX6 SoloLite, approximately 503 MiB RAM with no swap, approximately 2.43 GiB free USB storage, no TUN device, and a KOReader CA bundle. | Collected by the owner-approved diagnostic. | Userspace networking would be required; RAM/storage and TLS trust appear plausible, but the kernel is below the supported minimum for current Go/Tailscale. | Device report supplied by user, 2026-09-20 |
| D-011 | Run one version-only launch test using the checksum-verified official Tailscale 1.102.4 ARM package. | The owner chose to test the current binary despite the unsupported kernel. | The test must not start `tailscaled`, create state, authenticate, or enable Funnel. Failure ends the maintained-Tailscale route; it does not justify an old public-facing release. | User, 2026-09-20 |
| D-012 | Both official Tailscale 1.102.4 ARM executables successfully start on the Paperwhite 3 and report their versions with exit status 0. | Observed in the version-only KUAL test. | The maintained binary is launch-compatible despite the unsupported 3.0.35 kernel; daemon networking, stability, and support remain unproven. | Device report supplied by user, 2026-09-20 |
| D-013 | Run a time-bounded `tailscaled` test in userspace mode with in-memory ephemeral state, no login, no Funnel, and test log uploads disabled. | The owner authorized the recommended intermediate daemon test. | The script must stop only its own process, remove temporary artifacts, and report selected health/resource facts without retaining raw daemon logs. | User, 2026-09-20 |
| D-014 | The temporary userspace daemon test passed its bounded health criteria: local API socket present, expected logged-out status, stable for 15 seconds, stable 13.6 MiB RSS and six threads, no fatal/panic lines, and complete cleanup. | Observed in the KUAL daemon report. | Proceed to deliberate node-registration design; three generic error-classified lines remain unexplained and should be watched during authenticated testing. The 577 MiB virtual size is address-space reservation, not measured physical RAM use. | Device report supplied by user, 2026-09-20 |
| D-015 | Use the isolated `/mnt/us/extensions/pageturner-tunnel/` deployment for this experiment. | The owner installed and successfully ran the launch and daemon checks from this location. | Tailscale files remain removable and separate from system directories and KOReader plugins. | User action, 2026-09-20 |
| D-016 | Use private Tailscale Serve instead of Funnel; install/connect Tailscale on the iPhone. | The owner prefers the private network and does not use another phone VPN; least complication is the priority. | No public endpoint. Both phone and Kindle must be connected to the tailnet; private-browser behavior still needs actual-device testing. | User, 2026-09-21 |
| D-017 | Register the Kindle with a one-off, non-ephemeral, pre-approved auth key file and delete that file after successful use. | The Kindle has no interactive browser/SSH setup; an auth key avoids storing account credentials. | Persistent node state remains under the isolated extension; the key must never be shared or committed. | User authorized starting Tailscale setup, 2026-09-21 |
| D-018 | Kindle tailnet registration succeeded after correcting the process-check wrapper and restarting the device. | Owner reported successful registration, auth-key deletion and visibility in the admin console. | Persistent node state is now security-sensitive; preserve it during file updates. | User, 2026-09-22 |
| D-019 | Serve configuration must start/reuse Tailscale, expose interactive HTTPS approval, and have bounded waits. | With the old script, Tailscale started successfully but Serve appeared stuck. Tailscale 1.102.4 source confirms first HTTPS use may print an admin URL and block awaiting capability approval; old output was redirected invisibly. | Configure script now shows reconnection progress, HTTPS approval URL, 120-second approval counter, and explicit success/failure/timeout; reset/status calls have 15-second bounds. Device retest pending. | User report and source inspection, 2026-09-22 |
| D-020 | HTTPS Certificates have been enabled for the tailnet through the admin console. | The owner completed the first-time HTTPS enablement after the old Serve command appeared to wait. | The machine FQDN can appear in public Certificate Transparency logs while endpoint access remains private; revised configure/status scripts still await copying and device retest. | User, 2026-09-22 |

## Proposed decisions
| ID | Proposal | Alternatives / trade-offs | Recommendation |
|---|---|---|---|
| P-001 | Superseded by D-016: expose the listener through Funnel. | Avoided because private Serve meets the use case with only the phone VPN step. | Do not implement. |
| P-002 | Run read-only model/kernel/CPU/memory/storage checks before selecting or installing a current Tailscale binary. | Installing immediately is faster but risks incompatibility on an unknown Kindle. | Approve. |
| P-003 | Superseded by D-016: keep Funnel active only during supervised testing. | No Funnel will be enabled. | Do not implement. |
| P-004 | Install a dedicated minimal KUAL extension at `/mnt/us/extensions/pageturner-tunnel/`, rather than modifying system directories or coupling the experiment to a general Tailscale/KOReader plugin. | The community packages are convenient but include unrelated SSH/proxy/route behavior and broader lifecycle assumptions. An isolated extension is easier to inspect and remove. | Approve. |
| P-005 | Store binaries and node state beneath the dedicated extension, but put PID/socket runtime files under `/tmp`; use no Tailscale SSH, exit-node, route acceptance, or KOReader proxy flags. | System installation is less removable; the stock KUAL extension defaults to Tailscale SSH. | Approve. |
| P-006 | Register with a one-use, non-ephemeral, preauthorized auth key, delete the transferred auth-key file immediately after registration, and retain only Tailscale's node state until rollback. | QR login avoids an auth-key file but requires additional UI integration; a reusable key increases exposure. | Confirmed as D-017. |

## Assumptions and constraints
| ID | Item | Type | Validation needed |
|---|---|---|---|
| A-001 | KUAL can launch a diagnostic script and write its results to USB storage; interactive SSH is not configured. | Assumption | Harmless KUAL output-file test. |
| A-002 | Tailscale daemon networking may function despite the unsupported Linux 3.0.35 kernel, for example because of vendor backports. The 1.102.4 executables launch successfully, but this does not establish daemon stability or official support. | High-risk assumption | Time-bounded, logged userspace-daemon smoke test with no login or persistent state. |
| A-003 | The new tailnet will permit MagicDNS/HTTPS and private Serve access. | Constraint | Verify after registration. |
| A-004 | Serve's proxy request fits the plugin's strict bodyless-request parser and 4 KiB header cap. | Assumption | OPTIONS and POST integration tests. |
| A-005 | Available RAM and storage are sufficient for `tailscaled`, its state, and KOReader running together. | Assumption | Read-only memory/storage checks and supervised measurement. |

## Data model
No new application data model. Tailscale introduces persistent node identity/state and private key material on the Kindle; it must be excluded from source control and be revocable after the spike.

## Workflows and interfaces
1. Inspect target compatibility without changing device state.
2. Select a maintained compatible Tailscale build and transfer it to an isolated Kindle directory.
3. Start `tailscaled` without SSH, exit-node, subnet-route, or global proxy features; authenticate the node.
4. Start Page Turner with a book foregrounded.
5. Configure private Serve HTTPS to proxy only to `http://127.0.0.1:8088` (subject to proving loopback reachability with the plugin's firewall behavior).
6. Connect the iPhone Tailscale app and configure the PWA with the generated `https://<node>.<tailnet>.ts.net` endpoint and token.
7. Test preflight, one Next, one Back, wake lock, latency, errors, suspend/resume, tailnet disconnect, and daemon resource use.
8. Disable Serve and stop/remove the experimental daemon/state as selected by the rollback decision.

Interfaces remain bodyless `OPTIONS` preflight and authenticated bodyless `POST /next|/back`. HTTP `202` means accepted, not visibly completed. Timeouts remain uncertain and are never automatically retried.

## Edge cases and failure behavior
- Incompatible binary/kernel: stop before authentication or Serve enablement.
- Proxy adds excessive headers or a request body: reject safely; do not loosen parser without review.
- Timeout after dispatch: report uncertainty and inspect the Kindle; no retry.
- Kindle sleeps or Wi-Fi drops: endpoint may be unavailable; do not queue commands or alter sleep settings.
- Unexpected non-tailnet reachability: disable Serve immediately and inspect configuration; Funnel must remain off.
- Serve or daemon persists after test: verify disablement and revoke/remove the node if required.

## Acceptance criteria
- [ ] Current Tailscale compatibility and resource use are measured on the target Kindle.
- [ ] The Serve endpoint is reachable only from authorized tailnet devices; Funnel, SSH, exit node, subnet routing, file serving, and general proxy remain disabled.
- [ ] PWA preflight succeeds from the exact GitHub Pages origin.
- [ ] One Next and one Back each produce exactly one visible page turn through private Serve.
- [ ] Foreground wake lock coexists with private Serve control on the actual iPhone.
- [ ] Wrong/missing tokens cannot turn a page.
- [ ] Timeout/offline states remain honest and trigger no retry or queue.
- [ ] Normal KOReader controls and suspend/resume remain usable.
- [ ] Serve can be disabled and the pre-spike state restored.

## Open questions
- [x] Q-010 Private Tailscale Serve is selected instead of Funnel; the owner uses no other phone VPN and has connected the iPhone Tailscale app.
- [x] Q-001 Firmware 5.12.3 reports Linux 3.0.35-lab126, ARMv7/32-bit, about 503 MiB RAM, and about 2.43 GiB available USB storage.
- [x] Q-002 SSH is not configured; initial checks must run through a KUAL script that writes results to a manually transferable file.
- [x] Q-003 Superseded: temporary Funnel public exposure was once accepted; private Serve is now selected and Funnel must remain off.
- [x] Q-004 The owner created a Tailscale account/tailnet and connected the iPhone app.
- [ ] Q-005 After the test, should node state be retained for follow-up tests or removed and revoked immediately?
- [x] Q-006 The isolated `/mnt/us/extensions/pageturner-tunnel/` location is confirmed by successful device tests.
- [x] Q-007 One-use, non-ephemeral, pre-approved auth-key registration is selected; the key file is deleted after successful registration.
- [x] Q-008 The owner authorized a no-daemon, no-login launch test of the current official ARM binaries despite the unsupported kernel; both executables launched successfully.
- [x] Q-009 The owner authorized a time-bounded userspace-daemon test with temporary in-memory state, no login, and automatic shutdown.

## Decision history
| Date | Change |
|---|---|
| 2026-09-20 | Created the spike specification after the owner selected Tailscale Funnel for the next experiment. |
| 2026-09-20 | Recorded Paperwhite 3/KUAL/KOReader, manual file transfer, planned new tailnet, and acceptance of temporary public exposure; narrowed unknowns to runtime compatibility and access method. |
| 2026-09-20 | Owner approved minimal read-only device diagnostics; SSH is not configured, so diagnostics will use a removable KUAL extension and output file. |
| 2026-09-20 | Recorded firmware 5.12.3 and proposed an isolated Page Turner KUAL extension location plus minimal one-use-key authentication. |
| 2026-09-20 | Owner authorized implementation of the diagnostic-only KUAL package; created it under `kindle-kual/pageturner-tunnel/`. |
| 2026-09-20 | Recorded diagnostic results. RAM, storage, ARMv7, and CA bundle are plausible; TUN is absent and Linux 3.0.35 is below the Linux 3.2 minimum of the Go runtime used by maintained Tailscale releases. |
| 2026-09-20 | Owner authorized a version-only launch test. Prepared official Tailscale 1.102.4 ARM binaries after verifying archive SHA-256; no daemon-start action is included. |
| 2026-09-20 | First launch attempt was inconclusive: the Kindle's older `timeout` utility requires `-t 15` and interpreted bare `15` as a program. Neither Tailscale binary executed. Corrected the test wrapper without changing either binary. |
| 2026-09-20 | Corrected launch test passed: both official 1.102.4 ARM executables reported versions and exited 0 on Linux 3.0.35. This is launch evidence only, not daemon/Funnel support or official compatibility. |
| 2026-09-20 | Owner authorized the temporary logged-out daemon test; added an isolated userspace/in-memory KUAL action with automatic cleanup and classified reporting. |
| 2026-09-20 | Temporary daemon test passed: userspace daemon and local API remained alive for 15 seconds at stable 13.6 MiB RSS, logged-out CLI status was reachable, no fatal/panic was classified, and cleanup removed process/socket/log. Three error-classified lines remain unexplained. |
| 2026-09-20 | Owner reconsidered public Funnel exposure in favor of a private network and indicated phone Tailscale activation may be acceptable. Proposed Serve HTTPS instead; paused public enablement pending confirmation, preserving prior approvals as history. |
| 2026-09-21 | Confirmed private Serve and connected the iPhone app; superseded Funnel/public-exposure decisions without deleting history. Began isolated Kindle registration using a one-off auth-key file rather than account credentials. |
| 2026-09-22 | First persistent registration attempt exposed an old-BusyBox process-verification bug: `tailscaled` started successfully, but the wrapper misclassified it as stopped and unlinked its socket. Registration never consumed the key. Corrected liveness/ownership checks; a Kindle restart is the selected safe cleanup before retry. |
| 2026-09-22 | Owner reports successful Kindle registration after restart and corrected wrapper; auth key was deleted and `pageturner-kindle` appears in the admin console. |
| 2026-09-22 | Old script successfully started Tailscale but Serve appeared stuck with no screen output. Upstream 1.102.4 source shows HTTPS enablement can block awaiting interactive approval. Added Kindle-screen stages/URL/countdown, timestamped logs and finite command timeouts; retest pending. |
| 2026-09-22 | Owner enabled HTTPS in the Tailscale admin console and will copy the revised configure/status scripts. No revised-script or Serve-success evidence yet. |
