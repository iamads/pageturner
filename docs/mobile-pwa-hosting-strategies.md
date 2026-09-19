# Mobile PWA hosting strategies

> Status: Options under investigation; no production architecture selected
> Updated: 2026-09-19
> Scope: Compare hosting and connection alternatives before selecting an architecture.

## Correction: Kindle HTTPS is not universally required

The earlier comparison overstated the browser restrictions. Chrome's [Local Network Access documentation](https://developer.chrome.com/blog/local-network-access) describes a permission-gated mixed-content exemption for requests to private IP literals and `.local` names, with rollout beginning in Chrome 142. An HTTPS frontend may therefore call an HTTP LAN endpoint without a Kindle certificate in supported Chrome configurations. Ordinary CORS still applies, including the preflight triggered by `Authorization`.

The reported Chrome 151 `TypeError: Failed to fetch` after 2 ms does **not** distinguish mixed content, denied local-network permission, OS network permission, or rejected CORS preflight. An independent 401 probe proves listener reachability only; it does not prove the browser POST never reached the server. The existing plugin definitely lacks CORS/OPTIONS support, so a scoped CORS experiment and exact DevTools error inspection should precede TLS investment.

This is Chrome platform documentation, **not** evidence that Safari or the owner's iOS 26.6 Home Screen app supports the same exemption. Chrome on iPhone must not be assumed to behave like desktop Chrome. The phone's secure frontend must still acquire wake lock and send commands in the same installed app for the phase gate.

### Simpler alternatives to evaluate first

| Alternative | Setup / advantage | Limit / decision needed |
|---|---|---|
| HTTPS Pages → HTTP Kindle, local-network permission + narrow CORS | No Kindle certificates or TLS server; potentially only OPTIONS/CORS changes | Supported Chrome behavior; exact target-iPhone policy unknown. Token remains unencrypted on the LAN |
| HTTP page + API hosted on Kindle | Same-origin, no CORS or certificates; minimal runtime infrastructure | Standard wake lock/service worker unavailable; would require relaxing the wake-lock requirement (for example manually changing Auto-Lock), not currently approved |
| iOS Shortcut making an HTTP POST | A small native-client experiment can avoid browser mixed-content/CORS restrictions and reuse the API | Not the requested PWA or a demonstrated continuous foreground wake-lock control screen; target-device test required |
| Publicly trusted certificate for an owned hostname resolving to the Kindle's LAN IP | Can avoid installing a private CA on the phone; DNS-01 issuance does not require exposing Kindle ports publicly | Still needs Kindle TLS, domain/DNS control, certificate renewal and local resolution; changes raw-IP UX. Split/local DNS or public private-address records have operational trade-offs |
| Native app / thin native wrapper using native HTTP | Can avoid browser restrictions while offering foreground idle-timer control | Packaging/signing/installation effort; scope change, not necessarily easier for a personal prototype |
| Cloud relay or an always-on local bridge | Browser only contacts a conventional HTTPS endpoint | Adds runtime infrastructure; conflicts with direct phone+Kindle-only requirement |

Changing HTTP fetch to WebSocket does not reliably remove secure-context/mixed-content restrictions. WebRTC would require a substantial Kindle transport implementation. `no-cors` is not a solution: the bearer header and readable acknowledgement contract must remain intact.

**Current experiment:** the supplied Chrome console error identified a rejected CORS preflight (details below). The owner then authorized the narrowly scoped OPTIONS/CORS implementation. It is implemented and locally tested but not yet copied to or verified on the Kindle. Test the same HTTPS-frontend/HTTP-Kindle path on desktop and the actual iPhone before selecting TLS or changing product requirements.

## Requirements held constant

Both strategies must preserve these confirmed constraints:

- Phone talks directly to the Kindle; no laptop or cloud command relay at runtime.
- Installed iPhone PWA with foreground Screen Wake Lock while the app is visible.
- Existing bearer-token authentication remains required.
- Commands are sent once and are never automatically retried or queued.
- No Kindle sleep, Wi-Fi, or unrelated KOReader behavior changes.
- Trusted local-network use only; no public exposure of the Kindle endpoint.

Screen Wake Lock and service workers require a browser **secure context**. Avoiding CORS alone is therefore insufficient: a plain-HTTP Kindle page can be same-origin and still fail the wake-lock requirement.

## Strategy 1: GitHub Pages hosts the PWA; PWA calls the Kindle

### Shape

```text
PWA/assets:  https://iamads.github.io/pageturner/
Commands:    http://<kindle-address>:<port>/next
             http://<kindle-address>:<port>/back
             (HTTPS fallback if target-browser policy requires it)
```

GitHub Pages supplies the secure frontend origin. The browser sends authenticated requests from that public HTTPS origin directly to a private-LAN Kindle endpoint. GitHub never receives or relays commands.

### Current evidence

The PWA is live at `https://iamads.github.io/pageturner/`. Desktop Chrome loaded it as a secure context and exposed Wake Lock and service-worker APIs.

The current Kindle endpoint is plain HTTP. The initial request failed in 2 ms with `TypeError: Failed to fetch`, while an independent HTTP probe reached the listener and received 401. That generic error alone did not identify the browser's failure layer.

The owner subsequently supplied this Chrome console error:

```text
Access to fetch at 'http://192.168.0.102:8088/next' from origin
'https://iamads.github.io' has been blocked by CORS policy:
Response to preflight request doesn't pass access control check:
No 'Access-Control-Allow-Origin' header is present on the requested resource.
```

This identified a **CORS preflight response missing the allowed-origin header**, not a demonstrated TLS requirement. After the scoped CORS plugin update was installed, the owner reports successful visible control from the Pages PWA in desktop Chrome. This validates preflight, authenticated POST, and direct desktop-to-Kindle HTTP operation in that environment.

### How the preflight works and the proposed fix

Because the frontend and Kindle have different origins and the command uses an `Authorization` header, the browser first sends a permission check resembling:

```http
OPTIONS /next HTTP/1.1
Origin: https://iamads.github.io
Access-Control-Request-Method: POST
Access-Control-Request-Headers: authorization
```

The preflight has **no bearer token** and must never dispatch a page turn. The previously deployed plugin checked authentication before distinguishing OPTIONS, so an ordinary unauthenticated preflight received 401 without CORS headers. This was not evidence that the user entered the wrong token. The current branch handles the narrow preflight before command authentication; actual POSTs still authenticate normally.

**Implemented locally; device verification pending:** Recognize bodyless OPTIONS only for `/next` and `/back`, validate the exact origin, requested POST method, and supported request headers, then return a response such as:

```http
HTTP/1.1 204 No Content
Access-Control-Allow-Origin: https://iamads.github.io
Access-Control-Allow-Methods: POST
Access-Control-Allow-Headers: Authorization
Vary: Origin
```

After a successful preflight, the browser can send the actual command:

```http
POST /next HTTP/1.1
Origin: https://iamads.github.io
Authorization: Bearer <user-entered-token>
Content-Length: 0
```

The plugin must still validate the token and preserve its reader/pending-turn guards. Responses to the allowed-origin POST—including authentication and reader-state errors—also need `Access-Control-Allow-Origin: https://iamads.github.io` so JavaScript can read the result. Adding the header only to OPTIONS is insufficient.

Guardrails for this proposed change:

- Do not require the bearer token on preflight, but always require it on page-turn POSTs.
- Do not use wildcard origins, reflect arbitrary origins, enable arbitrary methods/headers, or grant access to other endpoints.
- The allowlist is an **origin**, `https://iamads.github.io`, not a URL path: CORS cannot distinguish `/pageturner/` from another page on that same origin. The token remains the authorization boundary.
- An OPTIONS success only grants browser permission to attempt a command; it does not authenticate the command or turn a page.
- Do not use `no-cors`, place tokens in URLs, or automatically retry failed commands. A POST accepted by the server can still appear as a browser error if its response lacks CORS headers.
- HTTP still exposes the token to observers of LAN traffic; the trusted-network restriction remains.
- Test local-network permission and the complete installed-app path separately on the actual iPhone. Desktop Chrome evidence is not Safari/Home Screen evidence.

**Decision status:** The owner authorized and installed this scoped CORS experiment. Desktop Chrome now works. Authentication and page-turn guards remain unchanged, and no PWA code or TLS changed. The iPhone result below prevents selecting this as the production architecture yet.

### iPhone WebKit result

The owner reports failure in both Safari and Firefox Focus on the iPhone. Firefox Focus diagnostics captured:

```text
User agent: Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X)
  AppleWebKit/605.1.15 ... FxiOS/155 ... Version/26.4
Frontend origin: https://iamads.github.io
Secure context: true
Display mode: browser
Wake Lock API: true
Service worker: true
Endpoint: http://192.168.0.102:8088
Wake state: Wake lock inactive
Last event: back fetch failed after 4 ms: TypeError: Load failed
```

All browsers on iOS use WebKit, so Safari and Firefox Focus failing is consistent with one shared platform restriction rather than two independent implementations. Desktop Chrome's local-network HTTP exemption cannot be assumed to exist in WebKit. The 4 ms failure is consistent with blocking before a useful HTTP exchange, but the evidence is not yet conclusive because matching Kindle transport logs and Safari Web Inspector output were not supplied.

Next diagnostics, in order:

1. Correlate one phone tap with `PageTurner: transport` lines. No new connection/request strongly supports pre-network browser/OS blocking; OPTIONS or POST lines identify a later layer.
2. On the phone, directly navigate to `http://192.168.0.102:8088/next` without a token. A displayed 401 cannot turn a page and proves direct phone-to-listener HTTP navigation/local-network access. Failure points to Wi-Fi isolation or iOS/app local-network permission before mixed-content analysis.
3. Confirm both devices use the same non-guest Wi-Fi and review iOS **Settings → Privacy & Security → Local Network** for the tested browser where exposed.
4. Capture Safari's exact Console/Network error using Web Inspector from a Mac if available.
5. Verify the OS version in **Settings → General → About**. The supplied UA says `iPhone OS 18_7`, while the earlier owner report was iOS 26.6 and the Focus UA also says `Version/26.4`; UA fields are not sufficient to resolve that discrepancy.
6. Only after transport is understood, install the PWA and test wake-lock acquisition/idle/background return. `Wake Lock API: true` with `Wake state: inactive` is capability detection, not a passed wake test.

If direct HTTP navigation works but no transport request appears for the HTTPS Pages fetch, trusted HTTPS on the Kindle becomes the leading standards-compliant PWA path. If HTTPS setup is undesirable, iOS Shortcut/native control or relaxing the wake-lock/PWA requirement are scope alternatives, not equivalent fixes.

### Changes required to make it viable

1. First test whether the target phone permits local-network HTTP from the secure frontend. If it does not, add HTTPS/TLS with a certificate trusted by the iPhone and matching the configured IP address or hostname.
2. Add narrowly scoped CORS responses for exactly `https://iamads.github.io`.
3. Handle `OPTIONS` preflight for the `Authorization` header without authenticating the preflight or weakening authentication on the actual command POST.
4. Investigate and support applicable browser private-network-access permission/preflight behavior on the target iPhone.
5. Keep the token in user-controlled runtime storage; never put it in GitHub Pages assets, URLs, logs, or repository settings.

CORS does not itself override mixed-content blocking. However, where a browser provides the documented local-network permission exemption, scoped CORS plus that permission may suffice without TLS.

### Pros

- Static frontend deployment and updates are easy and independent of Kindle file copies.
- The app shell remains reachable when the Kindle listener is stopped or asleep.
- GitHub Pages provides a publicly trusted secure frontend context without installing a frontend certificate.
- Existing PWA hosting and deployment workflow already work.
- Frontend diagnostics and updates can be released without modifying the plugin.
- Retains explicit Kindle IP/port configuration, matching the originally requested UX.

### Cons

- Browsers without a usable local-network mixed-content exemption still need trusted Kindle HTTPS, including certificate provisioning.
- Cross-origin `Authorization` requests require CORS and preflight implementation.
- Public-origin-to-private-network browser restrictions add another platform-specific failure layer beyond CORS.
- If TLS is needed, the browser must accept the Kindle certificate for an IP address or hostname that may change with DHCP.
- More moving parts: Pages availability/cache, CORS policy, preflight, local-network permission, token handling, and Kindle TLS if required.
- Initial install/update normally depends on internet access to GitHub Pages. Offline shell behavior after installation still needs a product decision and testing.
- A permissive CORS mistake could unnecessarily broaden which web origins can attempt authenticated requests.

### Security and operational notes

- CORS is not authentication. The bearer token remains mandatory on `/next` and `/back`.
- CORS should allow only the exact Pages origin, supported methods, and required headers.
- The static host must never receive the token; browser requests go directly to the Kindle.
- Changing the Pages origin or adding a custom domain requires updating the Kindle's allowed origin.
- A timed-out request remains uncertain and must never be replayed automatically.

## Strategy 2: Kindle hosts the PWA and command API

### Shape

```text
PWA/assets:  https://<kindle-address>:<port>/
Commands:    https://<kindle-address>:<port>/next
             https://<kindle-address>:<port>/back
```

The plugin serves both static PWA files and authenticated commands over the same HTTPS scheme, host, and port. The user opens this Kindle URL and adds that origin to the iPhone Home Screen. GitHub Pages is not part of runtime operation.

### Plain-HTTP variant

Serving both page and API from `http://<kindle-ip>:8088` would remove cross-origin CORS because page and commands share an origin. It is useful only as a limited control experiment:

- Screen Wake Lock and service workers generally remain unavailable because the remote Kindle HTTP origin is not a secure context.
- Adding the HTTP page to the Home Screen does not make it securely hosted.
- It does not satisfy the confirmed mobile-phase wake-lock outcome.

For the intended product, the Kindle-hosted strategy therefore means **same-origin HTTPS**, not merely serving HTML from the current HTTP listener.

### Changes required to make it viable

1. Validate KOReader's bundled LuaSec/OpenSSL server capabilities and acceptable resource behavior on the actual Kindle.
2. Add nonblocking TLS handshake/read/write handling without blocking KOReader's UI loop.
3. Provision a certificate trusted by the iPhone and matching a stable Kindle IP address or hostname.
4. Serve a small, fixed allowlist of PWA assets with correct content types and bounded request handling.
5. Keep `/next` and `/back` bearer-token protected; static shell assets may be public to the trusted LAN.
6. Ensure the page and commands use the exact same scheme, host, and port. Splitting them across ports creates different origins and reintroduces CORS.
7. Test service-worker scope, Home Screen installation, wake lock, listener lifecycle, sleep/reconnect, and certificate behavior on the target iPhone.

### Pros

- Same-origin page and commands eliminate CORS and command preflight.
- Avoids the public-to-private cross-origin request path and its private-network-access policy layer.
- Phone + Kindle operation can work without internet or an external static host.
- One origin simplifies endpoint configuration: the app can derive its API base from `location.origin`.
- Certificate and connectivity failures are surfaced when opening the app origin, rather than only after a command tap.
- Service worker, wake lock, assets, and API can be tested as one combined deployment.
- No frontend origin allowlist needs maintenance when a public hosting domain changes.

### Cons

- Trusted HTTPS is still mandatory; same-origin hosting does not remove certificate work.
- A private CA typically requires installing a profile on the iPhone and explicitly enabling full trust. A browser-warning bypass is not sufficient evidence of a secure context.
- IP-address certificates must be regenerated if DHCP changes the Kindle address unless a stable reservation or trusted hostname is established.
- The plugin becomes responsible for TLS, static files, content types, caching, and additional request parsing on a resource-constrained device.
- Frontend updates require updating files on the Kindle rather than only pushing GitHub Pages.
- Initial loading/install requires the Kindle listener to be running and reachable.
- KOReader's normal sleep/listener lifecycle may make the origin unavailable. A cached shell can improve launch behavior but cannot send commands to a sleeping listener.
- Bundled TLS server support is source precedent, not yet actual-device evidence; nonblocking handshake integration may be more complex than the current plain TCP server.

### Security and operational notes

- Continue requiring the bearer token even on the same origin; another device on the LAN may load public assets.
- Serve only fixed bundled assets—never arbitrary filesystem paths.
- Apply existing request-size, client-count, timeout, logging, firewall, and lifecycle limits to TLS/static requests.
- Do not package the bearer token in JavaScript, HTML, the service-worker cache, or a manifest.
- Prefer a stable DHCP reservation for an IP certificate, or a stable local hostname whose certificate behavior is proven on iOS.
- Certificate generation, private keys, trust profiles, renewal, and removal need explicit setup documentation.

## Comparison

| Concern | GitHub Pages frontend + Kindle API | Kindle-hosted page + API |
|---|---|---|
| Secure frontend context | Already provided by Pages | Requires trusted Kindle HTTPS |
| Trusted HTTPS on Kindle | Browser-dependent; test permission-gated HTTP first | Required for a secure Kindle-hosted origin |
| CORS/preflight | Required and narrowly scoped | Not required if exact same origin |
| Private-network cross-origin policy | Applies and requires testing | Avoided for same-origin requests |
| Internet dependency | Usually for install/update; offline shell undecided | None after local certificate/setup |
| Frontend updates | Push to Pages | Copy/update Kindle plugin assets |
| App available while listener is off | Shell can remain available | Only cached shell may be available |
| Endpoint setup | User enters Kindle IP/port | Can derive from app origin |
| Kindle implementation complexity | CORS/API; TLS only if required by target browser | TLS + static hosting/API |
| Browser-policy complexity | Higher | Lower after certificate trust |
| Certificate/IP-change burden | Certificate burden only if TLS is needed; IP changes still require endpoint updates | Present |
| Runtime path | Phone → Kindle; Pages only serves assets | Phone → Kindle only |
| Current status | Works in desktop Chrome; iPhone WebKit fetch fails in ~4 ms, exact layer pending logs | Not implemented or device-tested |

## Preliminary assessment

If trusted Kindle HTTPS is feasible, same-origin Kindle hosting removes two entire browser-policy layers: CORS/preflight and public-origin-to-private-network requests. It therefore appears architecturally simpler at runtime and better aligned with phone + Kindle-only/offline operation.

Its cost is greater Kindle plugin responsibility and less convenient frontend deployment. The simpler HTTP + CORS path now works in desktop Chrome but fails in iPhone WebKit. If logs confirm WebKit blocks before reaching the plugin while direct HTTP navigation works, TLS server capability, certificate setup, stable addressing, and target-iPhone secure-context behavior should be the next PWA experiment.

## Questions to resolve before selecting either strategy

- Will the owner accept installing and explicitly trusting a private CA profile on the iPhone?
- Can the router reserve a stable IP for the Kindle, or is a stable trusted hostname preferable?
- Must the installed control shell open without internet when the Kindle listener is currently unavailable?
- Is copying frontend updates to the Kindle acceptable, or is independent web deployment important?
- How should the token be retained, if at all, between app launches?
- Does KOReader 2026.03 on the actual Kindle include usable nonblocking TLS server support within acceptable resource limits?

No phase gate is passed by documenting these options. The actual-iPhone combined connectivity and wake-lock experiment remains required.
