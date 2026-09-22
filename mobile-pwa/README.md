# Mobile PWA feasibility harness

This is the phase-2 phone experiment described in [`../docs/mobile-pwa-handoff.md`](../docs/mobile-pwa-handoff.md). It supports both a direct local-network Kindle endpoint and the private Tailscale HTTPS endpoint required by the tested iPhone. Android direct connectivity remains a non-blocking experiment, not an assumed capability.

## What it tests

- Whether the installed app is a secure context and exposes Screen Wake Lock.
- Whether the PWA can camera-scan and strictly validate the Kindle's versioned endpoint/token payload without sending a command.
- Whether the same app can send one authenticated `POST /next` or `POST /back` through either a direct Kindle IP or a private Tailscale hostname.
- Wake-lock acquisition, browser release, visibility return, and explicit session end.
- Browser errors and deployment facts without recording the bearer token.

The token is held only in page memory. Reloading or terminating the app requires another scan or manual entry. Commands are never retried, queued, or intercepted by the service worker. A timeout is reported as uncertain because the Kindle may already have accepted the turn.

## QR pairing

Choose **Scan Kindle pairing QR**, grant camera permission, and point the rear camera at the QR shown after **Start Page Turner**. A valid payload has exactly the supported version plus an endpoint and session token. The PWA validates both using the same endpoint/token rules as manual entry, configures the controls, stops all camera tracks, and sends no network request until Next or Back is tapped.

Camera access requires the secure deployed PWA and an explicit user action. Scanning stops on success, cancellation, page backgrounding, or unload. Manual entry remains available if permission is denied or scanning fails. The QR decoder is vendored under `mobile-pwa/vendor/` and served locally with the PWA; no camera frame or payload is sent to a third party.

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

The tested iPhone WebKit path blocks the Pages PWA's direct HTTP request before it reaches the Kindle, so that device currently requires private Tailscale Serve. This result must not be generalized to Android: test direct HTTP there first. The plugin's CORS preflight remains narrowly restricted to the published Pages origin, commands and Authorization header.

## Desktop smoke check

From the repository root:

```sh
python3 -m http.server 4173 --directory mobile-pwa
```

Open `http://localhost:4173`. Localhost is treated specially as potentially trustworthy by desktop browsers, but this does **not** reproduce the iPhone-to-Kindle deployment and is not phase evidence. Stop this development server before any phone-only proof.

Run endpoint and pairing-payload validation tests with:

```sh
node --test tests/test_pwa_endpoint.mjs
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

## Actual-iPhone procedure

After a reachable HTTPS deployment succeeds:

1. In Safari on the actual phone, open the Pages URL and capture **Spike diagnostics**.
2. Add the app to the Home Screen, launch it there, and confirm `Secure context: yes` and `Display mode: standalone`.
3. Open a book and manually start Page Turner. Confirm the Kindle QR says **Private Tailscale** and shows the expected `*.ts.net` endpoint below it.
4. Tap **Scan Kindle pairing QR**, grant camera permission, and scan. Confirm the PWA reports that pairing was accepted and no page turns during scanning.
5. Dismiss the QR and close Kindle menus. Start the wake lock, leave the app visible longer than the existing Auto-Lock interval, and do not change that setting.
6. Tap Next exactly once, then Back exactly once. Observe the Kindle; HTTP 202 alone is not enough.
7. Stop and manually restart Page Turner, rescan, and verify the old token no longer authorizes a command. Test malformed/foreign QR and camera denial with manual entry still available.
8. Capture browser symptoms separately for camera, certificate/trust, local-network permission, and CORS/preflight failures. Copied diagnostics omit the token.
9. Background/return and manual lock/unlock. Confirm the app either reacquires the wake lock or truthfully reports failure, and that any active camera stream stops. End the session explicitly.
10. Verify the Pages-hosted app uses no laptop command relay/runtime dependency before calling the combined spike successful.

Do not repeatedly tap after an uncertain result. Never paste the token into screenshots, issue reports, URLs, or browser-console logs.

## Non-blocking Android procedure

On an available Android device, record the model, Android version, Chrome version and whether the app is running in-browser or installed. Record QR camera permission and scan behavior. With both devices on the same Wi-Fi, try the direct Kindle endpoint first (`192.168.x.x` defaults to HTTP/8088). Record local-network permission, preflight, browser error, plugin transport evidence, one coordinated Next/Back result and foreground wake-lock behavior. Only test the Tailscale endpoint as a fallback or comparison. Android results inform transport selection but do not block the current owner/iPhone phase gate.

## Success boundary

This harness passes P2-G0 only when authenticated next/back and foreground wake lock coexist in the installed app on the primary target iPhone, without a laptop command relay/runtime dependency, and the owner accepts the private Tailscale setup. Android testing is a separate non-blocking learning objective. Building or loading these files alone is not a pass.
