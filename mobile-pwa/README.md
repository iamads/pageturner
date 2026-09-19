# Mobile PWA feasibility harness

This is the smallest phase-2 experiment described in [`../docs/mobile-pwa-handoff.md`](../docs/mobile-pwa-handoff.md). It is deliberately a diagnostic harness, not evidence that direct iPhone-to-Kindle control works.

## What it tests

- Whether the installed app is a secure context and exposes Screen Wake Lock.
- Whether the same app can send one authenticated `POST /next` or `POST /back` directly to the configured Kindle IP/port.
- Wake-lock acquisition, browser release, visibility return, and explicit session end.
- Browser errors and deployment facts without recording the bearer token.

The token is held only in page memory. Reloading or terminating the app requires re-entry. Commands are never retried, queued, or intercepted by the service worker. A timeout is reported as uncertain because the Kindle may already have accepted the turn.

## Important expected blocker

Serving this harness from trusted HTTPS gives Wake Lock a secure context, but a request to the current `http://<kindle-ip>:8088` API may be blocked as mixed content before reaching the Kindle. If a request does reach the current API from another origin, its `Authorization` header requires a CORS preflight that the plugin does not yet support.

Those are separate failures. Do not disable token authentication, use `no-cors`, or treat an HTTP-only page and a separate HTTPS wake-lock demo as success. No TLS/CORS/plugin change has been selected by adding this harness.

## Desktop smoke check

From the repository root:

```sh
python3 -m http.server 4173 --directory mobile-pwa
```

Open `http://localhost:4173`. Localhost is treated specially as potentially trustworthy by desktop browsers, but this does **not** reproduce the iPhone-to-Kindle deployment and is not phase evidence. Stop this development server before any phone-only proof.

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
3. Add the app to the Home Screen, launch it there, and confirm `Secure context: yes` and `Display mode: standalone`.
4. Start the wake lock after a tap. Leave the app visible and idle longer than the phone's existing Auto-Lock interval; do not change that setting for the test.
5. Enter the current Kindle IP/port and token. With a book foregrounded and Page Turner listening, tap Next exactly once, then Back exactly once. Observe the Kindle; HTTP 202 alone is not enough.
6. Capture the exact browser symptom separately for mixed-content, certificate/trust, local-network permission, and CORS/preflight failures. The copied diagnostics omit the token.
7. Background/return and manual lock/unlock. Confirm the app either reacquires while the session is still wanted or truthfully reports failure. End session explicitly.
8. Verify the Pages-hosted app uses no laptop command relay/runtime dependency before calling the combined spike successful.

Do not repeatedly tap after an uncertain result. Never paste the token into screenshots, issue reports, URLs, or browser-console logs.

## Success boundary

This harness passes P2-G0 only when direct authenticated next/back and foreground wake lock coexist in this installed app on the target phone, without a laptop command relay/runtime dependency, and the owner accepts the required hosting/certificate setup. Building or loading these files alone is not a pass.
