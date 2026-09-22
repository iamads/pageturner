# Mobile PWA connection strategies — consolidated comparison

> Status: Brainstorming and feasibility; no production transport selected
> Updated: 2026-09-19
> Scope: All hosting, certificate, relay, VPN, native-client, and P2P options discussed so far.
> This update consolidates existing discussion/research only. No new external checks, installation, or deployment.

## 1. Requirements and decision boundaries

### Confirmed

- Keep an extensible **iPhone PWA**, not just a one-command launcher.
- Standard **foreground Screen Wake Lock is non-negotiable**. The OS may revoke it; background/manual-lock execution is not required.
- Internet connectivity during reading is acceptable.
- No running laptop dependency during use.
- Kindle Wi-Fi IP can change, including when changing networks. Do not require a new certificate for each IP.
- Preserve authentication, normal KOReader navigation, settings, Wi-Fi management, and sleep.
- Do not automatically retry uncertain commands or replay old turns after reconnect.
- Ask for confirmation before new external/device checks, downloads, installations, or account/public-endpoint changes.

### Rejected or deferred

- **Rejected:** iOS Shortcut as the product interface; native iOS app/wrapper; manual hostname/DNS/certificate setup.
- **Last resort only:** Kindle-hosted plain HTTP. It does not meet the current standard wake-lock requirement and cannot silently replace it.
- **Open:** Tailscale Serve versus Funnel, custom relay versus managed tunnel, and WebRTC/P2P feasibility.
- **Not authorized:** public Kindle exposure, VPN installation, or deployment of any new service. Accepting internet access does not automatically authorize these.
- The original direct-only/no-public-exposure roadmap assumptions need explicit revision if a relay or public tunnel is selected. No outcome gate has passed.

## 2. What we actually know

1. GitHub Pages serves the frontend securely at `https://iamads.github.io/pageturner/`.
2. The initial desktop Chrome request failed CORS preflight. Scoped OPTIONS/CORS was implemented in the plugin without removing POST authentication.
3. The owner reports successful Kindle control from the PWA in desktop Chrome after that update.
4. iPhone Safari/Firefox Focus failed the HTTP endpoint fetch. Focus reported `TypeError: Load failed` after 4 ms, secure context true, browser display mode, Wake Lock API available but **inactive**.
5. Direct iPhone navigation to `http://192.168.0.102:8088/next` returned/logged 401 at 21:54. A PWA tap at 21:56 had no matching connection log before listener shutdown at 21:57.
6. This establishes phone-to-listener HTTP reachability and no observed delivery for the PWA attempt. Browser/OS policy blocking is strongly implicated; the exact Safari policy message was not captured. Do not treat log absence as a complete diagnosis of every possible browser/network policy.
7. The exact iPhone OS/build remains unresolved: the original owner report was iOS 26.6, while the supplied UA included `iPhone OS 18_7` and `Version/26.4`. Verify Settings rather than choosing a UA field.
8. No combined installed-iPhone command + active wake-lock/idle test has passed. TLS, Tailscale, relay, and WebRTC paths have not been tested on the owner's Kindle.

### Corrections preserved from the discussion

- HTTPS-page → HTTP-LAN fetch is **not universally prohibited**: Chrome documents permission-gated local-network mixed-content exemptions. Desktop success is consistent with that behavior; it is not Safari evidence.
- CORS cannot itself override mixed-content/network policy. It did fix the observed Chrome preflight obstacle.
- An HTTPS **frontend** is needed for standard wake lock here. An HTTPS **server on the Kindle** is not universally required: an outbound secure relay or WebRTC channel can preserve the secure PWA without one.
- Same-origin hosting removes CORS, not the secure-context requirement.
- VPN encryption does not make an `http://` URL into an HTTPS URL in the browser's security model.
- Raw UDP/TCP is not exposed to an ordinary Safari PWA. Protocol libraries and WebAssembly do not grant missing browser socket privileges.

## 3. At-a-glance shortlist

“Wake lock compatible” below means the architecture can retain a secure PWA origin, **not** that actual-device wake behavior is proven.

| Candidate | Wake lock compatible? | Main advantage | Main cost/risk | Current position |
|---|---|---|---|---|
| Tailscale Serve | Yes | Managed stable private HTTPS; reuse HTTP plugin | Phone VPN plus Kindle daemon compatibility | Researched; candidate if phone app acceptable |
| Tailscale Funnel | Yes | Managed stable public HTTPS; no phone VPN | Public exposure, daemon/resources, external relay | Researched; needs exposure approval |
| Custom secure relay | Yes | No inbound Kindle TLS or stable LAN address | Own server/protocol/auth/availability | Conceptual; likely simplest custom architecture |
| Managed reverse tunnel | Yes | Reuse HTTP API; managed public HTTPS | Compatible tunnel client, exposure, service dependency | Conceptual; Funnel is a concrete researched example |
| WebRTC data channel | Yes | Potential direct P2P; no public IP certificate | Native Kindle peer, signaling, possible TURN | Conceptual; compatibility unresearched |

These are alternatives, not a selected implementation plan. The numbered catalogue below also preserves rejected, failed, and supporting options.

## 4. Hosting and direct HTTP/HTTPS

### S01 — GitHub Pages PWA → Kindle HTTP, with CORS/local-network permission

**Shape:** secure public frontend sends bodyless authenticated POSTs directly to the Kindle's current LAN IP.

**Pros:** smallest plugin change; easy independent frontend updates; no Kindle TLS/certificates; retains IP/port setup; now works in desktop Chrome.

**Cons:** target-browser network policy can prevent delivery; cross-origin Authorization requires preflight; token is plaintext on the LAN; IP must be updated when it changes.

**Wake lock:** available to the HTTPS frontend, but that alone does not make command transport work.

**Status:** implemented and owner-reported working on desktop Chrome; failed in tested iPhone browsers. Not a viable demonstrated target-phone solution.

### S02 — GitHub Pages PWA → Kindle HTTPS API

**Pros:** keeps existing frontend hosting and command API; HTTPS removes the current insecure-endpoint issue; easier frontend updates than Kindle hosting.

**Cons:** Kindle needs TLS termination, a matching trusted certificate, and addressing/renewal setup; still cross-origin, so CORS and local-network/browser permission tests remain. Manual certificate approaches were rejected.

**Wake lock:** compatible.

**Status:** direct manual TLS not implemented; managed HTTPS through Serve/Funnel is a distinct candidate below.

### S03 — Kindle hosts both page and API over plain HTTP

**Pros:** same-origin; no CORS, certificates, internet host, or relay; IP can be entered anew on each network; minimal conceptual architecture.

**Cons:** remote Kindle HTTP is not a secure context; standard wake lock/service workers are generally unavailable. Loading the initial page requires the listener to be reachable; updates require copying assets to Kindle.

**Wake lock:** fails the current requirement. Home Screen installation does not make HTTP secure. Manual Auto-Lock changes are not equivalent.

**Status:** owner-designated last resort, not approved under current requirements.

### S04 — Kindle hosts both page and API over HTTPS

**Pros:** exact same origin removes CORS/preflight; potentially no runtime internet dependency; API address can be derived from `location.origin`; one combined secure deployment.

**Cons:** TLS plus static asset hosting on a constrained device; certificate/addressing setup; Kindle file-copy frontend updates; initial install needs a reachable listener. A cached shell cannot control a sleeping Kindle.

**Wake lock:** compatible if the phone fully trusts the origin.

**Status:** unimplemented; manual certificate setup rejected. Static assets must be allowlisted—never expose config files or arbitrary filesystem paths.

## 5. Certificate/addressing variants considered

These support S02/S04; they are not complete transports themselves.

### S05 — Private CA + certificate for the Kindle IP

**Pros:** no purchased domain; direct local HTTPS; potentially offline after setup.

**Cons:** phone profile/full-trust installation; private-key management; certificate needs an IP SAN matching the URL. DHCP reservation helps only on that network; changed IPs require certificate changes. Clicking past a warning does not prove a secure context.

**Status:** rejected because IPs change and setup is burdensome.

### S06 — Stable hostname/local DNS or mDNS + private CA

**Pros:** certificate identifies a stable hostname instead of changing Wi-Fi IPs; no reissue for each IP change if resolution stays correct.

**Cons:** DNS/mDNS discovery and phone trust still need setup and testing across networks; local hostname alone is not a trusted certificate; renewal remains necessary.

**Status:** manual hostname/DNS/certificate management rejected.

### S07 — Owned hostname + publicly trusted certificate, e.g. DNS-01 issuance

**Pros:** no private CA profile on phone; hostname certificate survives IP changes; DNS-01 does not require exposing the Kindle's ports for issuance.

**Cons:** domain/DNS control, renewal/key deployment, and correct local/private resolution; split DNS or public records containing private IPs introduce network-dependent issues. Kindle still needs TLS termination.

**Status:** manual management rejected. Tailscale-managed `*.ts.net` addressing is being considered separately.

## 6. Relays, polling, and tunnels

### S08 — Custom cloud command relay with a persistent outbound Kindle connection

```text
HTTPS PWA → authenticated relay ← outbound TLS connection from Kindle
```

**Pros:** no inbound Kindle port or server certificate; changing Wi-Fi IP is irrelevant; no phone VPN app; same or different networks work; preserves extensible PWA and foreground wake lock.

**Cons:** service hosting, authentication/pairing, maintenance, latency, internet dependency, and Kindle nonblocking outbound connection management. Unless end-to-end payload encryption is deliberately added, the application relay can read commands; TLS on each leg is not end-to-end encryption.

**Safety:** bind messages to the active reading session, expire them promptly, use command IDs/acknowledgements as needed, and never replay stale turns. A stale connection must not be mistaken for guaranteed delivery. The relay need not receive book contents.

**Status:** conceptual; internet accepted, but server/provider/deployment not selected. Likely simplest custom architecture, not yet validated.

### S09 — Relay with Kindle polling or long-polling instead of a persistent socket

**Pros:** outbound HTTPS only; may reuse existing HTTP client facilities; less persistent-protocol work than a custom WebSocket client; tolerates changing IPs.

**Cons:** short polling adds latency and repeated radio/CPU work; long-polling still requires nonblocking integration and timeout/reconnect handling. A durable queue could cause dangerous late page turns after sleep.

**Wake lock:** compatible on the secure phone frontend.

**Status:** conceptual variant of S08. Poll interval, expiry, session binding, and power cost are unresolved; never poll through blocking calls in the reader UI thread.

### S10 — Managed reverse tunnel, including an SSH-based tunnel to a server

```text
HTTPS PWA → stable HTTPS gateway → outbound Kindle tunnel → local HTTP API
```

**Pros:** reuses the existing request/response API; stable frontend endpoint despite IP changes; avoids implementing Kindle TLS in Lua. A managed gateway can handle browser-facing certificates.

**Cons:** tunnel software must run on Kindle; additional daemon/process lifecycle and credentials; relay latency/availability; often public exposure. An SSH reverse tunnel alone is not browser HTTPS—the remote end still needs a suitable HTTPS gateway.

**Status:** conceptual general option. Tailscale Funnel is the specific researched managed-tunnel candidate. No other provider was selected or tested.

### S11 — Always-on laptop/local bridge or proxy

**Pros:** puts TLS/tunneling and heavier dependencies on a capable machine; can reuse the Kindle HTTP API.

**Cons:** adds another runtime device, maintenance, and potentially another addressing problem; stops working when that bridge is unavailable.

**Wake lock:** possible through a trusted HTTPS frontend/proxy.

**Status:** laptop-dependent use rejected. A different always-on local appliance has not been approved as a substitute.

## 7. Tailscale and other overlay networks

Detailed sources and inspected community code: [Tailscale research](tailscale-research.md).

### S12 — Ordinary Tailscale or ZeroTier network, still using HTTP

**Pros:** private peer connectivity, stable overlay addressing, encrypted network traffic, tolerance of changing underlying IPs; may use direct paths.

**Cons:** native network software/configuration on devices; daemon/resources and key lifecycle; overlay encryption does not change Safari's treatment of an HTTP fetch from HTTPS. ZeroTier compatibility was not researched.

**Wake lock:** frontend can remain secure, but the HTTP browser-policy problem is not resolved merely by adding a VPN.

**Status:** not sufficient on its own. Do not confuse a private overlay IP with a public HTTPS endpoint.

### S13 — Tailscale Serve

```text
HTTPS PWA → private https://kindle.<tailnet>.ts.net
         → Kindle tailscaled/Serve → http://127.0.0.1:8088
```

**Pros:** stable hostname and managed certificates independent of Wi-Fi IP; private endpoint; reuse HTTP plugin/CORS/token; no custom relay implementation or Lua TLS server. Tailnet access rules add a protection layer.

**Cons:** Tailscale required and connected on phone and Kindle; VPN coexistence/account/node-key considerations; Kindle binary/kernel/resources unknown; browser private-network permissions still require testing. Traffic is not guaranteed to be peer-to-peer and may use encrypted relays.

**Wake lock:** compatible with the existing HTTPS Pages frontend.

**Changes:** PWA currently accepts IPv4 only and ports 1024–65535; hostname/443 support is needed. Review loopback-only mode, proxy-added headers/framing, sleep/reconnect, and rollback to LAN mode.

**Status:** researched; candidate if the phone Tailscale app is acceptable. No installation or certificate issuance.

### S14 — Tailscale Funnel

```text
HTTPS PWA → public *.ts.net endpoint → Funnel relay
         → Kindle tailscaled terminates TLS → local HTTP API
```

**Pros:** managed stable HTTPS with no phone VPN; no manual IP certificates; reuse HTTP API; no custom cloud command relay. Official docs describe encrypted forwarding with TLS terminating on the device, not decrypted by the Funnel relay.

**Cons:** public endpoint is reachable by anyone; token protection does not prevent resource exhaustion. Requires hardening the trusted-LAN server, controlling logging volume, and reviewing proxy behavior. Kindle daemon compatibility/resources, external-service availability/latency, beta status, and documented bandwidth/port restrictions remain relevant.

**Wake lock:** compatible.

**Status:** researched, not selected. Requires explicit public-exposure approval and revised guardrails. No Funnel or public endpoint enabled.

### Shared Tailscale compatibility caveats

- Community KOReader and KUAL projects exist; this is precedent, not proof for the owner's unknown model.
- Userspace networking avoids a TUN dependency, not the Go runtime's kernel/CPU requirements.
- Older Kindle kernels may not support current binaries; the community README's older minimum-kernel guidance is insufficient.
- Do not automatically enable SSH, exit nodes, accepted subnet routes, or global KOReader proxies for this use case.
- Normal Kindle sleep must remain normal sleep; a VPN does not authorize remote wake or keeping Wi-Fi awake.

## 8. Other browser protocols and P2P stacks

These are conceptual assessments, not new implementation research or Kindle compatibility results.

### S15 — Raw UDP or TCP / custom socket protocol

**Pros:** a native client and LuaSocket server could exchange tiny low-overhead messages; no HTTP/CORS layer at the protocol level.

**Cons:** a normal Safari PWA has no general-purpose raw UDP/TCP API. Installing on the Home Screen, using WebAssembly, or adding a service worker does not grant it. UDP also requires deliberate delivery/order/duplicate handling.

**Status:** unavailable for the requested ordinary PWA. A Kindle UDP listener alone cannot help.

### S16 — Plain WebSocket (`ws://`)

**Pros:** persistent bidirectional messages and a browser API; can replace repeated request setup.

**Cons:** insecure WebSocket connections from a secure page face mixed-content restrictions. It requires a new server/protocol and is not a dependable escape from the failed HTTP path.

**Status:** not recommended as a bypass; untested on target.

### S17 — Secure WebSocket (`wss://`)

**Pros:** browser-supported bidirectional secure channel; good fit for relay sessions and acknowledgements; HTTPS frontend retains wake lock.

**Cons:** TLS still terminates somewhere; direct Kindle WSS reintroduces certificate/server work. Through a cloud relay it inherits S08's service and failure-mode costs. Connection recovery does not grant exactly-once command delivery.

**Status:** useful transport inside another architecture, not an independent way to eliminate TLS setup everywhere.

### S18 — WebRTC data channel, potentially with a lightweight native Kindle component

```text
HTTPS PWA ←── authenticated signaling service ──→ Kindle peer
     ╰──────── encrypted data channel ───────────╯
```

**Pros:** genuine browser-accessible P2P candidate; commonly uses SCTP over DTLS over an ICE-selected UDP path; no browser-trusted IP certificate required on the Kindle. Certificate fingerprints are exchanged through signaling. IP changes need reconnection/ICE recovery rather than a new public IP certificate. Data-only channels do not need microphone/camera access. The PWA remains secure and wake-lock capable.

**Cons:** Kindle needs an ICE/DTLS/SCTP peer, not just a UDP listener. Requires authenticated signaling/pairing, native library packaging, resource/lifecycle validation, and possibly STUN/TURN. Direct connectivity is not guaranteed. Encryption alone does not authorize page turns; session binding, stale-message prevention, and acknowledgements remain necessary.

**Candidate library mentioned:** `libdatachannel`, for investigation only. No library compatibility, build, licensing/dependency review, or resource measurement has been performed.

**Status:** strongest conceptual non-HTTP direct-P2P alternative; substantially more engineering than raw UDP and potentially more than Tailscale or a simple relay.

### S19 — libp2p

**Pros:** peer identities, discovery, routing, transport abstractions, and relay mechanisms; potentially valuable for a larger multi-peer product.

**Cons:** browser peers still depend on supported transports such as WebRTC, WebTransport, or secure WebSockets; it does not grant raw sockets or bypass policy. Adds integration/protocol complexity for a one-phone/one-Kindle job and may still need relays.

**Wake lock:** compatible when frontend stays HTTPS.

**Status:** conceptual; no Safari/Kindle implementation researched. Probably more abstraction than this project needs.

### S20 — PeerJS / simple-peer

**Pros:** simplify browser-side WebRTC setup/signaling plumbing; reduce application boilerplate.

**Cons:** wrappers, not alternative network protocols; do not remove the Kindle native-peer requirement, signaling authentication, TURN needs, or WebRTC interoperability work. Library-specific signaling/protocol compatibility must be checked.

**Status:** potential helpers for S18, not standalone solutions. No evaluation performed.

### S21 — WebTorrent

**Pros:** browser-capable P2P file sharing using WebRTC; useful when distributing content among peers.

**Cons:** piece-based file distribution and swarm machinery are a poor fit for immediate authenticated next/back commands; inherits WebRTC/native-peer/infrastructure requirements.

**Wake lock:** an HTTPS frontend could retain it, but that does not make the command architecture appropriate.

**Status:** discussed and deprioritized conceptually; no implementation research.

### S22 — WebTransport / HTTP/3 datagrams / custom QUIC

**Pros:** secure streams and datagrams in supporting browsers; can support low-latency bidirectional applications.

**Cons:** not arbitrary UDP access. Needs a compatible secure server and target-browser support, which was not verified for this iPhone. Custom QUIC libraries cannot make a missing Safari API appear. Protocol/TLS packaging on Kindle may be substantial.

**Status:** conceptual; not established as a simpler alternative.

## 9. Non-PWA alternatives and attempted workarounds

### S23 — iOS Shortcut issuing HTTP POST

**Pros:** potentially quick native-client control of the existing API; avoids normal web-page CORS/mixed-content rules; configurable IP and token.

**Cons:** not the requested extensible PWA, not a demonstrated continuous wake-lock control screen; bodyless POST, local-network permissions, and token storage require device validation.

**Status:** explicitly rejected by owner as the product direction.

### S24 — Native iOS app or thin wrapper using native networking

**Pros:** can support configurable local HTTP and native foreground idle-timer control, with appropriate platform permissions/security configuration; large controls and future features possible.

**Cons:** signing, packaging, distribution, and native integration; a web view alone is not a guaranteed networking bypass—native networking must be deliberate. Replaces the requested delivery model.

**Status:** explicitly rejected by owner.

### S25 — Browser/security or wake-lock workarounds

| Idea | Apparent advantage | Why it is not an accepted solution |
|---|---|---|
| `fetch(..., {mode: "no-cors"})` | Avoid readable CORS errors | Cannot preserve the current Authorization-header/readable-acknowledgement contract; does not override mixed content |
| HTML forms, images, or iframes | Simple browser primitives | Different method/header/response capabilities and security restrictions; no demonstrated authenticated safe control path |
| Service-worker proxy/offline queue | Keep the PWA shell available | Not a privileged raw-network proxy; must never store/replay navigation commands |
| Home Screen installation alone | App-like launch | Does not turn an HTTP origin into a secure context or grant sockets |
| Browser-warning bypass/self-signed leaf | Avoid proper trust setup | Not sufficient evidence of a secure context or working installed PWA |
| Another iOS browser brand | Easy to try | The tested browsers share WebKit; brand switching is not proof of a different engine or policy. App permissions can differ, but this is not an architecture |
| Disable browser security/developer bypass | Expedite a lab test | Not a supported personal-reading deployment or validated secure-PWA path |
| Manual Auto-Lock setting / audio-video keep-alive | Keep a screen on without standard wake lock | Violates the current requirement or relies on fragile tricks; not approved |

These are recorded so future work does not repeatedly revisit them as unexplored easy fixes.

## 10. CORS implementation retained from the experiment

The working plugin accepts only the exact origin `https://iamads.github.io`, routes `/next` and `/back`, requested method POST, and requested header Authorization.

Example browser preflight, without a token:

```http
OPTIONS /next HTTP/1.1
Origin: https://iamads.github.io
Access-Control-Request-Method: POST
Access-Control-Request-Headers: authorization
```

Successful permission response:

```http
HTTP/1.1 204 No Content
Access-Control-Allow-Origin: https://iamads.github.io
Access-Control-Allow-Methods: POST
Access-Control-Allow-Headers: Authorization
Vary: Origin
```

- OPTIONS never turns a page. Actual POSTs require the bearer token and reader/pending-turn guards.
- Actual allowed-origin POST responses, including auth/reader errors, also need the allowed-origin header.
- CORS scopes origins, not paths within an origin: all pages at `https://iamads.github.io` share that origin. The token remains the authorization boundary.
- CORS is neither encryption nor protection against non-browser internet attackers.
- A successful acknowledgement means accepted for deferred navigation, not completed e-ink rendering.
- Browser failures after an accepted POST can be ambiguous. Never automatically retry.

## 11. Comparative assessment and next decisions

**Lowest likely custom application complexity:** S08/S09 secure relay, provided hosting/operations and the Kindle outbound client are acceptable.

**Most concrete existing-tool candidate:** S13 Serve, or S14 Funnel if phone-VPN installation is undesirable and public exposure is explicitly accepted. Community Kindle precedent exists, but hardware compatibility could eliminate either.

**Most interesting direct-P2P alternative:** S18 WebRTC, possibly assisted by S20; its native packaging and signaling cost must be established before investing. S19 libp2p does not automatically simplify a two-peer system.

**Not a target-phone solution as demonstrated:** S01 direct HTTP. **Does not satisfy wake lock:** S03 plain-HTTP-hosted page. **Owner rejected:** S05–S07 manual certificate/addressing work and S23/S24 non-PWA interfaces. **Browser-unavailable:** S15 raw sockets.

Questions before proceeding:

1. Which candidate should receive the next explicitly approved feasibility check: Tailscale, a custom relay, or WebRTC?
2. What are the Kindle model/kernel/CPU/resources, and is a current supported implementation compatible? Ask before checking the device.
3. Is a Tailscale app/VPN on the iPhone acceptable? If not, is public Funnel exposure acceptable after hardening?
4. If a custom relay is preferred, what hosting/account/maintenance costs are acceptable?
5. Can the selected design preserve sleep, reject stale commands, recover without duplicates, and pass both actual-iPhone command and wake-lock tests?

No recommendation here is a device compatibility claim, architecture selection, or authorization to deploy.

## 12. Evidence and references

- [Project roadmap](../roadmap.md) and [mobile handoff](mobile-pwa-handoff.md): requirements, device reports, and unresolved gates.
- [Tailscale research](tailscale-research.md): official Serve/Funnel/HTTPS docs, pinned community plugin source revisions, kernel/runtime caveats, and proposed compatibility checks.
- [Chrome Local Network Access](https://developer.chrome.com/blog/local-network-access): permission-gated private-IP mixed-content exemptions; not Safari evidence.
- [MDN Screen Wake Lock](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API): secure-context/visibility requirements and release behavior.
- [MDN mixed content](https://developer.mozilla.org/en-US/docs/Web/Security/Mixed_content): browser transport restrictions.
- [KOReader research](koreader-research.md): existing listener/navigation/lifecycle baseline.

WebRTC libraries, libp2p, PeerJS/simple-peer, WebTorrent, ZeroTier, and WebTransport were brainstormed conceptually, not subjected to fresh external compatibility research for this document.
