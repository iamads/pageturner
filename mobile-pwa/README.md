# Page Turner web app

Hosted app: **https://iamads.github.io/pageturner/**

This directory is the static phone client for the Page Turner KOReader plugin. GitHub Pages serves these files directly; there is no command relay or backend service.

## Pairing flow

1. The Kindle QR links to the hosted app with `version`, Kindle endpoint, and session token in the URL fragment (`#…`).
2. URL fragments are not included in HTTP requests to GitHub Pages.
3. On load, `pairing.js` extracts and validates the fragment; `history.replaceState` removes it before any Kindle request.
4. `app.js` keeps the credentials only in page memory and sends an authenticated `POST /connect` directly to the Kindle endpoint.
5. HTTP 204 displays **Connected** and enables **Next**/**Back**. Failure is inline; **Retry connection** repeats only the non-mutating check.
6. Each page-control tap sends one authenticated request. Commands are never automatically retried or queued by the service worker.

The app does not access the camera or decode QR codes. Scanning is handled by the phone's native camera. Camera/browser software can still see the original pairing link, so the QR/link must be treated as a session credential.

Reloading or closing the page loses the connection. Scan again or use **Enter connection manually**. The modal accepts:

```text
192.168.1.42
192.168.1.42:8089
http://192.168.1.42:8088
pageturner-kindle.<tailnet>.ts.net
https://pageturner-kindle.<tailnet>.ts.net
```

Direct IPv4 defaults to HTTP port 8088. A `*.ts.net` host defaults to HTTPS port 443. Paths, query strings, fragments, embedded credentials, HTTPS-to-IP, and HTTP-to-Tailscale combinations are rejected.

## Network behavior

The browser connects directly to the Kindle:

- **Private Tailscale Serve:** tested iPhone path; private HTTPS, phone and Kindle on the same tailnet.
- **Direct local HTTP:** supported by the app for trusted LAN use, but blocked by the tested iPhone WebKit path and not yet validated on Android.

CORS in the Kindle plugin allows only the exact production origin `https://iamads.github.io`, POST requests to `/connect`, `/next`, and `/back`, and the `Authorization` header.

## Foreground wake lock

**Start wake lock** requests the Screen Wake Lock API while the page is visible. Browsers/operating systems may deny or release it. The app reports the current state and tries to reacquire it when a requested session returns to visibility. It does not run page controls in the background or change global phone settings.

## Privacy and safety

- Credentials are never stored in local storage, IndexedDB, cookies, the service worker, or diagnostics.
- The pairing fragment is removed before the direct Kindle check.
- A `<meta name="referrer" content="no-referrer">` policy and fetch `referrerPolicy: "no-referrer"` provide additional protection.
- A page-turn timeout has an uncertain outcome; the app tells the user to inspect the Kindle and never retries automatically.
- The service worker caches only same-origin static GET assets and never intercepts Kindle POST requests.

## Local development

From the repository root:

```sh
python3 -m http.server 4173 --directory mobile-pwa
```

Open `http://localhost:4173`. This smoke check does not reproduce phone browser policy, private Tailscale, native-camera behavior, or actual Kindle page turns.

Run web-app tests with:

```sh
node --test tests/test_pwa_*.mjs
```

The controller tests use DOM/fetch doubles rather than a real mobile browser.

## Deployment

[`.github/workflows/pages.yml`](../.github/workflows/pages.yml) deploys only `mobile-pwa/` to GitHub Pages on relevant pushes to `main` (and the historical mobile-PWA branch). It runs the JavaScript tests before upload.

For a fork/self-hosted deployment, update both:

1. the project URL in `pageturner.koplugin/pageturner_pairing.lua`; and
2. `ALLOWED_ORIGIN` in `pageturner.koplugin/pageturner_http.lua`.

Deploy the frontend and plugin together. Do not put tokens in repository settings, source files, build variables, or query strings.
