# Page Turner web app

Hosted app: **https://iamads.github.io/pageturner/**

This directory is the static phone client for the Page Turner KOReader plugin. GitHub Pages serves these files directly; there is no command relay or backend service.

## Pairing flow

1. The Kindle QR links to the hosted app with `version`, Kindle endpoint, and session token in the URL fragment (`#…`).
2. URL fragments are not included in HTTP requests to GitHub Pages.
3. On load, `pairing.js` extracts and validates the fragment; `history.replaceState` removes it before any Kindle request.
4. `app.js` keeps the credentials only in page memory and sends an authenticated `POST /connect` directly to the Kindle endpoint.
5. HTTP 204 displays **Connected** and enables **Next**/**Back**. Failure is inline; **Retry connection** repeats only the non-mutating check.
6. Each page-control tap or accepted foreground `next`/`back` voice detection sends one authenticated request. Commands are never automatically retried or queued by the service worker.

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

## Foreground listening (work in progress)

**Start listening** requests a screen wake lock and microphone permission, then passes bounded mono PCM chunks from an AudioWorklet to a detector Worker. **Stop listening** releases the microphone, audio context, Worker, and wake lock. The app keeps the `Heard next`, `Heard back`, and `Heard sleep` toasts. While the app is visible and the Kindle connection is verified, `next` and `back` also use the same authenticated sender as the manual buttons. `sleep` remains toast-only and does not stop listening or suspend the Kindle. Same-word detections within 800 ms are suppressed; turns arriving during an in-flight request or without a verified connection are dropped, never queued. No recording or detection-history log is stored or uploaded. Browsers may interrupt capture/wake locks; foreground iPhone behavior still needs testing.

Stream 1 (UI/capture/command policy) is isolated from Stream 2 (model-specific Worker adapter) via PCM chunks and `next`/`back`/`sleep` events. To exercise Stream 1 without recognition, visit `http://localhost:4173/?voice-test=1`; the simulated command controls are developer-only, labeled as such, and rejected by the Worker on non-localhost origins.

**Choose exactly one detector in [`detector-config.js`](detector-config.js)** by setting `ACTIVE_DETECTOR` to `"sherpa"` (default) or `"vosk"`, then reload the app (close/reopen an installed PWA if it is showing older cached code). For a Mac dev-server comparison, edit only that constant and reload `http://localhost:4173/`; allow extra time for the first Vosk model download and for its completed-word results. There is no detector picker in the UI and the app's capture, toasts and guarded API dispatch are identical for both. The tiny config loads network-first with an offline cached fallback so switching it does not also require changing the service-worker version.

The bundled single-thread sherpa-onnx English WASM model runs fully on-device: `sherpa-detector.js` bridges streaming audio into the locally hosted decoder. Its runtime/model/keyword assets are versioned in the service worker's cache for offline use after successful installation. A model or microphone failure is reported inline and releases the session; a wake-lock-only fallback preserves foreground reading. **The runtime loaded and emitted a detection from local synthetic audio in Chrome, including a Worker startup with network emulation offline, but recognition on the actual iPhone and with the owner's voice is untested.** Locally synthesized single-word “sleep” triggered; “next” and “back” did not with the initial settings. Do not assume usable accuracy, memory or battery behavior before manual device testing.

The alternative `vosk-detector.js` uses a locally hosted Vosk browser ASR runtime and the small US English model, with an exact `next/back/sleep/[unk]` grammar. It emits only **completed, exact-word** recognition results, never unstable partial transcripts. Its ~39 MB compressed model is fetched only if Vosk is selected (not pre-cached on sherpa startup); first load can take longer and use substantially more memory, and offline Vosk initialization is not guaranteed. Vosk's bundled runtime also spawns an internal Worker, so the displayed bridge timings do not measure its inner decoder. This is an experiment, not an accuracy or iPhone compatibility guarantee.

For exact sherpa versions, artifact digests and local validation, see [`vendor/sherpa-onnx/PROVENANCE.md`](vendor/sherpa-onnx/PROVENANCE.md). The reproducible build helper is [`tools/build-sherpa-kws.sh`](../tools/build-sherpa-kws.sh) (Emscripten 4.0.23 and Python sentencepiece required only to rebuild, not to use the PWA). Vosk provenance is in [`vendor/vosk/PROVENANCE.md`](vendor/vosk/PROVENANCE.md). Both recognize only bare `next`, `back`, and `sleep`; only the app controller calls Kindle APIs, never the detector adapters.

### Manual iPhone check (after deploying the changed `mobile-pwa/`)

1. Open the updated HTTPS PWA in the foreground; if it was previously installed, close and reopen it to pick up the new service-worker cache. Keep the screen visible and test without connecting to the Kindle first.
2. Tap **Start listening**. Grant microphone permission. Wait for **Microphone listening** and a **Listening started** toast; loading 18 MB of local model/runtime assets may take a while on first use. If the model fails, the app shows a reason and offers **Keep screen awake without voice** instead of claiming to recognize speech.
3. Say the bare words **next**, **back**, **sleep** individually, with a short pause. Note which produce `Heard …` toasts and any unwanted toasts during ordinary quiet audio. Without a verified connection, no speech detection should move a Kindle page. Then pair with the Kindle, close its QR and menus, say **next** and **back** once each, and confirm one page turn each alongside the existing toasts. **Sleep** should still only show a toast.
4. Tap **Stop listening** and check **Microphone off**; try the manual buttons separately only when you intend to send a page turn. Retry after returning from another app if you want to observe iOS interruption behavior; background listening is not promised.
5. If recognition is poor, open **Spike diagnostics** while listening. `Audio processing` shows processed and dropped chunks and worst observed worker/queue time; this stores no audio and is not a detection log. Reload to receive the current service-worker cache (v9), then retry a short foreground session. Report detections/misses, diagnostics and any model/startup errors before adjusting thresholds. Voice-triggered turns are enabled, but real-device recognition quality remains unvalidated. A clean model load alone does not demonstrate usable accuracy.

These files are prepared locally; **they have not been pushed or tested on the iPhone**.

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
