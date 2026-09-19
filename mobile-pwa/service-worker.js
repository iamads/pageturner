const CACHE = "pageturner-spike-v1";
const SHELL = ["./", "index.html", "styles.css", "app.js", "manifest.webmanifest"];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(SHELL)));
});

self.addEventListener("activate", (event) => {
  event.waitUntil(caches.keys().then((names) => Promise.all(
    names.filter((name) => name.startsWith("pageturner-spike-") && name !== CACHE)
      .map((name) => caches.delete(name))
  )));
});

self.addEventListener("fetch", (event) => {
  // Never intercept, queue, or replay cross-origin requests or page-turn POSTs.
  if (event.request.method !== "GET" || new URL(event.request.url).origin !== self.location.origin) return;
  event.respondWith(caches.match(event.request).then((cached) => cached || fetch(event.request)));
});
