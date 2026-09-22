# Mobile PWA feasibility harness

This is the phase-2 phone experiment described in [`../docs/mobile-pwa-handoff.md`](../docs/mobile-pwa-handoff.md). It supports both a direct local-network Kindle endpoint and the private Tailscale HTTPS endpoint required by the tested iPhone. Android direct connectivity remains a non-blocking experiment, not an assumed capability.

## What it tests

- Whether the installed app is a secure context and exposes Screen Wake Lock.
- Whether a native phone camera opens the Kindle's HTTPS pairing link and the web app validates/extracts its credentials, then checks authentication without turning a page.
- Whether the same app can send one authenticated `POST /next` or `POST /back` through either a direct Kindle IP or a private Tailscale hostname.
- Wake-lock acquisition, browser release, visibility return, and explicit session end.
- Browser errors and deployment facts without recording the bearer token.

The token is held only in page memory. Reloading or terminating the app requires another scan or manual entry. Commands are never retried, queued, or intercepted by the service worker. A timeout is reported as uncertain because the Kindle may already have accepted the turn.

## Camera-link pairing

Use the phone's ordinary camera to scan the QR shown after **Start Page Turner**, then open its link to `https://iamads.github.io/pageturner/`. The PWA has no QR decoder or camera integration.

The link carries URL-encoded `version=1`, `endpoint` and `token` fields after `#`, never in a query. Fragments are not sent to GitHub Pages. The app immediately removes the fragment with `history.replaceState`, validates all fields, and keeps credentials only in memory. Invalid links are also cleared and send no request. Camera/browser software still sees the original link; history replacement does not guarantee deletion from camera history. Treat the entire link/QR as a secret.

A valid link automatically sends bodyless `POST /connect` with the bearer token. Only HTTP 204 shows **Connected** and enables Next/Back. Authentication failures, old plugins, network/browser failures and the three-second timeout show **Connection failed** inline, never a popup. **Retry connection** repeats only the safe check, never a turn. The check works while the Kindle QR/menu is open; close it before turning pages. Success proves authentication/reachability at that moment, not future connectivity or reader readiness.

**Enter connection manually** opens a modal with Kindle endpoint, masked token, **Connect**, and **Cancel**. Connect closes the modal, clears the token field and uses the same validation/check. Invalid input fails inline on the main page without a request. Cancel/Escape clears the entered token and preserves the current connection.

Native cameras usually open the browser, not necessarily an installed PWA. The OS decides this; credentials are not shared across browser/installed contexts. Reloading/reopening requires rescanning or manual entry. No network/Tailscale requirement changes.

## Endpoint formats

Enter the port in the endpoint field after a colon when a non-default port is needed. Accepted forms include:

```text
192.168.1.42
192.168.1.42:8089
http://192.168.1.42:8088
pageturner-kindle.<tailnet>.ts.net
pageturner-kindle.<tailnet>.ts.net:443
https://pageturner-kindle.<tailnet>.ts.net
```

A bare IPv4 address defaults to direct HTTP port 8088. A bare `*.ts.net` hostname defaults to HTTPS port 443. Paths, query strings, fragments, embedded credentials, HTTPS-to-IP and HTTP-to-Tailscale combinations are rejected. The endpoint and token remain in page memory only.

The tested iPhone WebKit path blocks the Pages PWA's direct HTTP request before it reaches the Kindle, so that device currently requires private Tailscale Serve. This result must not be generalized to Android: test direct HTTP there first. The plugin's CORS preflight remains narrowly restricted to the published Pages origin, `/next`, `/back`, `/connect`, POST and Authorization.

## Desktop smoke check

From the repository root:

```sh
python3 -m http.server 4173 --directory mobile-pwa
```

Open `http://localhost:4173`. Localhost is treated specially as potentially trustworthy by desktop browsers, but this does **not** reproduce the iPhone-to-Kindle deployment and is not phase evidence. Stop this development server before any phone-only proof.

Run endpoint/link validation and controller-flow tests (DOM/fetch doubles, not phone-browser evidence) with:

```sh
node --test tests/test_pwa_*.mjs
```

## GitHub Pages deployment

GitHub Pages is the owner-approved HTTPS host for this spike. [`.github/workflows/pages.yml`](../.github/workflows/pages.yml) publishes only this directory; it does not contain a command relay or a token.

One-time repository setup:

1. Push this branch to the GitHub repository.
2. In **Settings → Pages → Build and deployment**, choose **GitHub Actions** as the source.
3. Run **Deploy mobile PWA to GitHub Pages** from the Actions tab if the push did not trigger it.
4. Use the HTTPS URL shown by the workflow's `github-pages` deployment. For a project site it is normally `https://<owner>.github.io/<repository>/`.

The repository remote is `iamads/pageturner`, and Pages deploys through GitHub Actions at:

**https://iamads.github.io/pageturner/**

After the old account-level custom domain was removed, the project workflow had to be redeployed before this URL stopped returning 404. The live page and all shell assets now return HTTP 200 over HTTPS. The older `iamads/iamads.github.io` repository still has a tracked `CNAME` file containing `abhijeet.de` on its `master` Pages source branch; remove that file in the older repository before its next legacy Pages build if the domain should remain detached.

Do not add secrets to hosting configuration, repository variables, these files, or the workflow.

### Upgrading from the old in-PWA scanner

Deploy the new PWA and update the complete Kindle plugin together, preserving `config.lua` and Tailscale state. The new QR is a URL, not the old JSON payload, and requires the new authenticated `/connect` API. Cache **v4** drops the decoder and replaces cache-v3 assets. Before scanning, open the site, let the service worker update, then reload until the scanner is gone and **Enter connection manually** appears. Existing cache-v3 pages cannot parse the new link on their first load. Roll back both sides together and bump the cache version again if reverting.

## Actual-iPhone procedure

After a reachable HTTPS deployment succeeds:

1. In Safari on the actual phone, open the Pages URL and capture **Spike diagnostics**.
2. Add the app to the Home Screen, launch it there, and confirm `Secure context: yes` and `Display mode: standalone`.
3. Open a book and manually start Page Turner. Confirm the Kindle QR says **Private Tailscale** and shows the expected `*.ts.net` endpoint below it.
4. Scan with the native camera and open the link. Record whether the OS opens a browser or the installed app; do not assume handoff. Confirm the address no longer contains the fragment, **Connected** appears inline, and no page turns while the Kindle QR is open. Test manual modal entry separately in the installed context if needed.
5. Dismiss the QR and close Kindle menus. Start the wake lock, leave the app visible longer than the existing Auto-Lock interval, and do not change that setting.
6. Tap Next exactly once, then Back exactly once. Observe the Kindle; HTTP 202 alone is not enough.
7. Stop and manually restart Page Turner, rescan, and verify the old token fails the connection check. Test malformed links, manual modal Connect/Cancel/Escape, timeout, explicit retry and reload; no check should turn a page.
8. Capture native-camera link-opening symptoms separately from certificate/trust, local-network permission, and CORS/preflight failures. Copied diagnostics omit the token.
9. Background/return and manual lock/unlock. Confirm the app either reacquires the wake lock or truthfully reports failure. End the session explicitly.
10. Verify the Pages-hosted app uses no laptop command relay/runtime dependency before calling the combined spike successful.

Do not repeatedly tap after an uncertain result. Never paste the token or pairing link into screenshots, issue reports, shared URLs, or browser-console logs.

## Non-blocking Android procedure

On an available Android device, record the model, Android version, Chrome version and whether the app is running in-browser or installed. Record native-camera scan/link-opening behavior, display mode, and the inline connection-check result. With both devices on the same Wi-Fi, try the direct Kindle endpoint first (`192.168.x.x` defaults to HTTP/8088). Record local-network permission, preflight, browser error, plugin transport evidence, one coordinated Next/Back result and foreground wake-lock behavior. Only test the Tailscale endpoint as a fallback or comparison. Android results inform transport selection but do not block the current owner/iPhone phase gate.

## Success boundary

This harness passes P2-G0 only when authenticated next/back and foreground wake lock coexist in the installed app on the primary target iPhone, without a laptop command relay/runtime dependency, and the owner accepts the private Tailscale setup. Android testing is a separate non-blocking learning objective. Building or loading these files alone is not a pass.
