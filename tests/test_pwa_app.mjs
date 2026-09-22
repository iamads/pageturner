import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { parseConnection, consumePairingFragment } from "../mobile-pwa/pairing.js";

// Dependency-free DOM/fetch doubles exercise the actual app controller. Native
// dialog focus trapping, camera recognition and browser policy need device tests.
const html = readFileSync(new URL("../mobile-pwa/index.html", import.meta.url), "utf8");
const source = readFileSync(new URL("../mobile-pwa/app.js", import.meta.url), "utf8")
  .replace(/^import .*;\n/, "");
const token = "a".repeat(64);
const endpoint = "https://kindle.example.ts.net";
const fragment = (auth = token) => `#version=1&endpoint=${encodeURIComponent(endpoint)}&token=${auth}`;
const flush = () => new Promise((resolve) => setImmediate(resolve));
const response = (status, text = "") => ({status, text: async () => text});

function events(target = {}) {
  const listeners = new Map();
  target.addEventListener = (name, fn) => {
    if (!listeners.has(name)) listeners.set(name, []);
    listeners.get(name).push(fn);
  };
  target.emit = async (name) => {
    for (const fn of listeners.get(name) || []) await fn({preventDefault() {}});
  };
  return target;
}

function app(hash = "", {ignoreAbort = false} = {}) {
  const elements = new Map();
  let focused;
  for (const [tag, id] of html.matchAll(/<[^>]*?\bid="([^"]+)"[^>]*>/g)) {
    elements.set(id, events({
      value: "", textContent: "", dataset: {}, open: false,
      disabled: /\bdisabled\b/.test(tag), hidden: /\bhidden\b/.test(tag),
      focus() { focused = id; },
      showModal() { this.open = true; },
      close() { this.open = false; this.emit("close"); },
    }));
  }
  const location = new URL(`https://iamads.github.io/pageturner/${hash}`);
  const requests = [];
  const timers = new Map();
  const historyCalls = [];
  let clock = 0;
  const context = events({
    document: events({
      getElementById: (id) => { assert(elements.has(id), `missing element ${id}`); return elements.get(id); },
      visibilityState: "visible",
    }),
    navigator: {userAgent: "test"},
    location,
    history: {replaceState(state, title, url) {
      historyCalls.push([state, title, url]);
      location.href = new URL(url, location).href;
    }},
    parseConnection, consumePairingFragment, AbortController,
    Date, performance, isSecureContext: true,
    matchMedia: () => ({matches: false}),
    setTimeout(fn, delay) { const id = ++clock; timers.set(id, {fn, delay}); return id; },
    clearTimeout(id) { timers.delete(id); },
    fetch(url, options) {
      assert.equal(location.hash, "", "fragment must be scrubbed before any fetch");
      return new Promise((resolve, reject) => {
        requests.push({url, options, resolve, reject});
        if (!ignoreAbort) options.signal.addEventListener("abort", () => reject(new Error(`secret ${token}`)));
      });
    },
  });
  context.window = context;
  vm.runInNewContext(source, context, {filename: "app.js"});
  return {
    context, location, requests, timers, historyCalls,
    el: (id) => elements.get(id),
    focus: () => focused,
    async manual(endpointValue = endpoint, auth = token) {
      await elements.get("manual-connection").emit("click");
      elements.get("endpoint-input").value = endpointValue;
      elements.get("token").value = auth;
      await elements.get("connection-form").emit("submit");
    },
    async timeout() {
      const entry = [...timers.values()][0];
      assert.equal(entry.delay, 3000);
      entry.fn();
      await flush();
    },
  };
}

test("link boot scrubs history, checks once without a turn, and enables buttons only on 204", async () => {
  const a = app(fragment());
  assert.equal(a.location.href, "https://iamads.github.io/pageturner/");
  assert.deepEqual(a.historyCalls, [[null, "", "/pageturner/"]]);
  assert.equal(a.requests.length, 1);
  const check = a.requests[0];
  assert.equal(check.url, endpoint + "/connect");
  assert.equal(check.options.method, "POST");
  assert.equal(check.options.headers.Authorization, `Bearer ${token}`);
  assert.equal(check.options.credentials, "omit");
  assert.equal(check.options.redirect, "error");
  assert.equal(check.options.cache, "no-store");
  assert.equal(check.options.body, null);
  assert.equal(a.el("connection-state").dataset.state, "checking");
  assert.equal(a.el("next").disabled, true);
  await a.el("next").emit("click");
  assert.equal(a.requests.length, 1);
  check.resolve(response(204)); await flush();
  assert.equal(a.el("next").disabled, false);
  assert.equal(a.el("back").disabled, false);
  assert.match(a.el("connection-state").textContent, /^Connected/);
  assert.equal(a.el("connection-dialog").open, false);
  assert.equal(a.el("retry-connection").hidden, true);
  assert.equal(a.timers.size, 0);
});

test("plain visit and malformed link never fetch or enable turns", async () => {
  for (const hash of ["", "#token=" + token, fragment("short"), fragment() + "&version=1"]) {
    const a = app(hash);
    assert.equal(a.requests.length, 0);
    assert.equal(a.el("next").disabled, true);
    assert.equal(a.location.hash, "");
    if (hash) assert.match(a.el("connection-state").textContent, /Invalid pairing link/);
  }
});

test("401, old plugin and unexpected status fail inline without enabling control", async () => {
  for (const [status, message] of [[401, /Authentication rejected/], [404, /Update the Kindle plugin/], [202, /HTTP 202/]]) {
    const a = app(fragment());
    a.requests[0].resolve(response(status, token)); await flush();
    assert.equal(a.el("next").disabled, true);
    assert.equal(a.el("retry-connection").hidden, false);
    assert.equal(a.el("retry-connection").disabled, false);
    assert.match(a.el("connection-state").textContent, message);
    assert(!a.el("connection-state").textContent.includes(token));
    assert.equal(a.requests.length, 1);
  }
});

test("timeout and network failures redact errors, never retry automatically, allow explicit safe retry", async () => {
  for (const timedOut of [true, false]) {
    const a = app(fragment());
    if (timedOut) await a.timeout();
    else { a.requests[0].reject(new Error(token)); await flush(); }
    assert.equal(a.requests.length, 1);
    assert.equal(a.el("next").disabled, true);
    assert.equal(a.el("connection-state").dataset.state, "failed");
    assert(!a.el("connection-state").textContent.includes(token));
    assert(!a.el("diag-event").textContent.includes(token));
    const retry = a.el("retry-connection").emit("click");
    assert.equal(a.requests.length, 2);
    assert.equal(a.requests[1].url, endpoint + "/connect");
    a.requests[1].resolve(response(204)); await retry;
    assert.equal(a.el("next").disabled, false);
  }
});

test("manual modal closes and clears token before checking; invalid input fails inline", async () => {
  const a = app();
  await a.manual();
  assert.equal(a.el("connection-dialog").open, false);
  assert.equal(a.el("token").value, "");
  assert.equal(a.focus(), "manual-connection");
  assert.equal(a.requests.length, 1);
  a.requests[0].resolve(response(204)); await flush();
  assert.equal(a.el("next").disabled, false);
  await a.manual("https://evil.example", token);
  assert.equal(a.requests.length, 1);
  assert.equal(a.el("token").value, "");
  assert.equal(a.el("connection-dialog").open, false);
  assert.match(a.el("connection-state").textContent, /Connection failed/);
  assert.equal(a.el("next").disabled, true);
});

test("manual cancel and Escape clear input and preserve verified connection", async () => {
  const a = app(fragment());
  a.requests[0].resolve(response(204)); await flush();
  for (const escape of [false, true]) {
    await a.el("manual-connection").emit("click");
    assert.equal(a.el("connection-dialog").open, true);
    a.el("token").value = "b".repeat(64);
    if (escape) {
      await a.el("connection-dialog").emit("cancel");
      a.el("connection-dialog").close(); // native dialog default action
    } else await a.el("cancel-connection").emit("click");
    assert.equal(a.el("token").value, "");
    assert.equal(a.el("next").disabled, false);
    assert.equal(a.requests.length, 1);
  }
});

test("superseded checks and invalid subsequent links cannot re-enable stale credentials", async () => {
  const a = app(fragment(), {ignoreAbort: true});
  await a.manual(endpoint, "b".repeat(64));
  assert.equal(a.requests[0].options.signal.aborted, true);
  a.requests[0].resolve(response(204)); await flush();
  assert.equal(a.el("next").disabled, true);
  assert.equal(a.el("connection-state").dataset.state, "checking");
  a.location.hash = "#invalid";
  await a.context.emit("hashchange");
  a.requests[1].resolve(response(204)); await flush();
  assert.equal(a.el("next").disabled, true);
  assert.match(a.el("connection-state").textContent, /Invalid pairing link/);
});

test("new valid fragment is consumed in an existing page", async () => {
  const a = app();
  a.location.hash = fragment(); await a.context.emit("hashchange");
  assert.equal(a.requests.length, 1);
  a.requests[0].resolve(response(204)); await flush();
  assert.equal(a.el("next").disabled, false);
});

test("commands remain one-shot and uncertain on timeout; replacement checks can run during a turn", async () => {
  const a = app(fragment());
  a.requests[0].resolve(response(204)); await flush();
  const command = a.el("next").emit("click");
  assert.equal(a.requests[1].url, endpoint + "/next");
  assert.equal(a.el("next").disabled, true);
  await a.el("back").emit("click");
  assert.equal(a.requests.length, 2);
  await a.timeout(); await command;
  assert.match(a.el("command-state").textContent, /Uncertain result/);
  assert.equal(a.requests.length, 2);
  const second = a.el("back").emit("click");
  await a.manual(endpoint, "b".repeat(64));
  assert.equal(a.requests[3].url, endpoint + "/connect");
  a.requests[3].resolve(response(204)); await flush();
  assert.equal(a.el("next").disabled, true); // old turn still in flight
  a.requests[2].resolve(response(202)); await second;
  assert.equal(a.el("next").disabled, false);
  assert.match(a.el("command-state").textContent, /No page-turn command was sent/);
});

test("UI and cache no longer contain camera or decoder integration", () => {
  const worker = readFileSync(new URL("../mobile-pwa/service-worker.js", import.meta.url), "utf8");
  assert(!/jsQR|getUserMedia|scanner-video|scan-qr|diag-camera/.test(html + source + worker));
  assert.match(html, /<dialog[^>]+aria-labelledby="dialog-title"/);
  assert.match(html, /id="token"[^>]+type="password"/);
  assert.match(html, /id="connection-form"[^>]+method="dialog"/); // never default GET credentials to Pages
  assert.match(worker, /pageturner-spike-v4/);
});

test("worker removes old scanner caches and never handles authenticated POSTs", async () => {
  const source = readFileSync(new URL("../mobile-pwa/service-worker.js", import.meta.url), "utf8");
  const handlers = new Map();
  const deleted = [];
  let shell;
  vm.runInNewContext(source, {
    URL,
    self: {
      location: {origin: "https://iamads.github.io"},
      addEventListener: (name, fn) => handlers.set(name, fn),
      skipWaiting: async () => {},
      clients: {claim: async () => {}},
    },
    caches: {
      open: async () => ({addAll: async (files) => { shell = [...files]; }}),
      keys: async () => ["pageturner-spike-v3", "pageturner-spike-v4", "unrelated"],
      delete: async (name) => { deleted.push(name); },
    },
  });
  let pending;
  handlers.get("install")({waitUntil: (promise) => { pending = promise; }});
  await pending;
  assert(shell.includes("pairing.js"));
  assert(!shell.some((file) => /vendor|jsQR|#|token/.test(file)));
  handlers.get("activate")({waitUntil: (promise) => { pending = promise; }});
  await pending;
  assert.deepEqual(deleted, ["pageturner-spike-v3"]);
  for (const request of [
    {method: "POST", url: endpoint + "/connect"},
    {method: "POST", url: endpoint + "/next"},
    {method: "GET", url: endpoint},
  ]) {
    handlers.get("fetch")({request, respondWith() { assert.fail("must not intercept Kindle traffic"); }});
  }
});

test("wake lock release, foreground reacquisition and explicit end remain independent of pairing", async () => {
  const a = app();
  const locks = [];
  a.context.navigator.wakeLock = {request: async (type) => {
    assert.equal(type, "screen");
    const lock = events({released: false});
    lock.release = async () => { lock.released = true; await lock.emit("release"); };
    locks.push(lock);
    return lock;
  }};
  await a.el("start-session").emit("click");
  assert.match(a.el("wake-state").textContent, /Wake lock active/);
  a.context.document.visibilityState = "hidden";
  await locks[0].release();
  await a.context.document.emit("visibilitychange");
  assert.equal(locks.length, 1);
  a.context.document.visibilityState = "visible";
  await a.context.document.emit("visibilitychange");
  assert.equal(locks.length, 2);
  await a.el("end-session").emit("click");
  assert.equal(locks[1].released, true);
  assert.equal(a.el("wake-state").textContent, "Wake lock inactive");
  assert.equal(a.requests.length, 0);
});
