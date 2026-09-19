# Mobile PWA hosting strategies

> Status: Options under investigation; no production architecture selected
> Updated: 2026-09-19
> Scope: Compare the two hosting strategies considered so far. Additional strategies will be added before a decision.

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
Commands:    https://<kindle-address>:<port>/next
             https://<kindle-address>:<port>/back
```

GitHub Pages supplies the secure frontend origin. The browser sends authenticated requests from that public HTTPS origin directly to a private-LAN Kindle endpoint. GitHub never receives or relays commands.

### Current evidence

The PWA is live at `https://iamads.github.io/pageturner/`. Desktop Chrome loaded it as a secure context and exposed Wake Lock and service-worker APIs.

The current Kindle endpoint is plain HTTP. A request from the Pages app to `http://192.168.0.102:8088` failed in 2 ms with `TypeError: Failed to fetch`, while an independent HTTP probe reached the listener and received 401. This is consistent with the browser blocking the HTTPS-to-HTTP path before an application response. Exact browser-console policy text and target-iPhone behavior have not yet been captured.

### Changes required to make it viable

1. Add HTTPS/TLS to the Kindle endpoint with a certificate trusted by the iPhone and matching the configured IP address or hostname.
2. Add narrowly scoped CORS responses for exactly `https://iamads.github.io`.
3. Handle `OPTIONS` preflight for the `Authorization` header without authenticating the preflight or weakening authentication on the actual command POST.
4. Investigate and support applicable browser private-network-access permission/preflight behavior on the target iPhone.
5. Keep the token in user-controlled runtime storage; never put it in GitHub Pages assets, URLs, logs, or repository settings.

Adding CORS to the current HTTP server alone does **not** solve mixed-content blocking.

### Pros

- Static frontend deployment and updates are easy and independent of Kindle file copies.
- The app shell remains reachable when the Kindle listener is stopped or asleep.
- GitHub Pages provides a publicly trusted secure frontend context without installing a frontend certificate.
- Existing PWA hosting and deployment workflow already work.
- Frontend diagnostics and updates can be released without modifying the plugin.
- Retains explicit Kindle IP/port configuration, matching the originally requested UX.

### Cons

- The Kindle still needs trusted HTTPS, so this strategy does not avoid certificate provisioning.
- Cross-origin `Authorization` requests require CORS and preflight implementation.
- Public-origin-to-private-network browser restrictions add another platform-specific failure layer beyond CORS.
- The browser must accept the Kindle certificate for an IP address or hostname that may change with DHCP.
- More moving parts: Pages availability/cache, Kindle TLS, CORS policy, preflight, local-network permission, and token handling.
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
| Trusted HTTPS on Kindle | Required | Required |
| CORS/preflight | Required and narrowly scoped | Not required if exact same origin |
| Private-network cross-origin policy | Applies and requires testing | Avoided for same-origin requests |
| Internet dependency | Usually for install/update; offline shell undecided | None after local certificate/setup |
| Frontend updates | Push to Pages | Copy/update Kindle plugin assets |
| App available while listener is off | Shell can remain available | Only cached shell may be available |
| Endpoint setup | User enters Kindle IP/port | Can derive from app origin |
| Kindle implementation complexity | TLS + CORS/API | TLS + static hosting/API |
| Browser-policy complexity | Higher | Lower after certificate trust |
| Certificate/IP-change burden | Present | Present |
| Runtime path | Phone → Kindle; Pages only serves assets | Phone → Kindle only |
| Current status | HTTP command path blocked in desktop Chrome | Not implemented or device-tested |

## Preliminary assessment

If trusted Kindle HTTPS is feasible, same-origin Kindle hosting removes two entire browser-policy layers: CORS/preflight and public-origin-to-private-network requests. It therefore appears architecturally simpler at runtime and better aligned with phone + Kindle-only/offline operation.

Its cost is greater Kindle plugin responsibility and less convenient frontend deployment. This is not yet a selected architecture: TLS server capability, certificate setup, stable addressing, and target-iPhone secure-context behavior must be demonstrated before choosing it.

## Questions to resolve before selecting either strategy

- Will the owner accept installing and explicitly trusting a private CA profile on the iPhone?
- Can the router reserve a stable IP for the Kindle, or is a stable trusted hostname preferable?
- Must the installed control shell open without internet when the Kindle listener is currently unavailable?
- Is copying frontend updates to the Kindle acceptable, or is independent web deployment important?
- How should the token be retained, if at all, between app launches?
- Does KOReader 2026.03 on the actual Kindle include usable nonblocking TLS server support within acceptable resource limits?

No phase gate is passed by documenting these options. The actual-iPhone combined connectivity and wake-lock experiment remains required.
