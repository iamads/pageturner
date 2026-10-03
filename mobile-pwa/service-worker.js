const CACHE = "pageturner-spike-v9";
const SHELL = [
  "./", "index.html", "styles.css", "app.js", "endpoint.js", "pairing.js",
  "detector-config.js", "voice-session.js", "voice-capture-worklet.js",
  "voice-detector-worker.js", "sherpa-detector.js", "vosk-detector.js", "vendor/vosk/vosk.js",
  "vendor/sherpa-onnx/sherpa-onnx-kws.js", "vendor/sherpa-onnx/keywords.txt",
  "vendor/sherpa-onnx/sherpa-onnx-wasm-kws-main.js",
  "vendor/sherpa-onnx/sherpa-onnx-wasm-kws-main.wasm",
  "vendor/sherpa-onnx/sherpa-onnx-wasm-kws-main.data",
  "manifest.webmanifest",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((names) => Promise.all(
      names.filter((name) => name.startsWith("pageturner-spike-") && name !== CACHE)
        .map((name) => caches.delete(name))
    )).then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (event) => {
  // Never intercept, queue, or replay cross-origin requests or page-turn POSTs.
  if (event.request.method !== "GET" || new URL(event.request.url).origin !== self.location.origin) return;
  // Switching detectors in detector-config.js must not require editing another file.
  // Refresh the tiny config online; use the last local copy when offline.
  if (new URL(event.request.url).pathname.endsWith("/detector-config.js")) {
    event.respondWith(fetch(event.request).then((response) => {
      if (response.ok) {
        const copy = response.clone();
        event.waitUntil(caches.open(CACHE).then((cache) => cache.put(event.request, copy)));
      }
      return response;
    }).catch(() => caches.match(event.request)));
    return;
  }
  event.respondWith(caches.match(event.request).then((cached) => cached || fetch(event.request)));
});
