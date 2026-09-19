const $ = (id) => document.getElementById(id);

const elements = {
  form: $("connection-form"), protocol: $("protocol"), host: $("host"),
  port: $("port"), token: $("token"), connection: $("connection-state"),
  start: $("start-session"), end: $("end-session"), wake: $("wake-state"),
  next: $("next"), back: $("back"), command: $("command-state"),
  origin: $("diag-origin"), secure: $("diag-secure"), display: $("diag-display"),
  visibility: $("diag-visibility"), wakeApi: $("diag-wake-api"),
  worker: $("diag-worker"), endpoint: $("diag-endpoint"), event: $("diag-event"),
  copy: $("copy-diagnostics"),
};

let connection = null;
let wakeSentinel = null;
let sessionWanted = false;
let requestPending = false;

function displayMode() {
  if (matchMedia("(display-mode: standalone)").matches || navigator.standalone === true) return "standalone";
  return "browser";
}

function timestamped(message) {
  return `${new Date().toISOString()} — ${message}`;
}

function record(message) {
  elements.event.textContent = timestamped(message);
}

function updateControls() {
  const enabled = Boolean(connection) && !requestPending;
  elements.next.disabled = !enabled;
  elements.back.disabled = !enabled;
}

function updateDiagnostics() {
  elements.origin.textContent = location.origin;
  elements.secure.textContent = window.isSecureContext ? "yes" : "no";
  elements.display.textContent = displayMode();
  elements.visibility.textContent = document.visibilityState;
  elements.wakeApi.textContent = "wakeLock" in navigator ? "available" : "unavailable";
  elements.worker.textContent = "serviceWorker" in navigator ? "available" : "unavailable";
}

function parseConnection() {
  const protocol = elements.protocol.value;
  const host = elements.host.value.trim();
  const port = Number(elements.port.value);
  const token = elements.token.value;
  if (!/^(?:\d{1,3}\.){3}\d{1,3}$/.test(host)) throw new Error("Enter the Kindle IPv4 address.");
  if (host.split(".").some((part) => Number(part) > 255)) throw new Error("Enter a valid IPv4 address.");
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error("Port must be 1024–65535.");
  if (!/^[A-Za-z0-9_-]{32,128}$/.test(token)) throw new Error("Enter the 32–128 character Page Turner token.");
  return {baseUrl: `${protocol}://${host}:${port}`, protocol, host, port, token};
}

elements.form.addEventListener("submit", (event) => {
  event.preventDefault();
  try {
    connection = parseConnection();
    elements.connection.textContent = `Configured for ${connection.baseUrl}`;
    elements.endpoint.textContent = connection.baseUrl;
    elements.token.value = "";
    record(`Connection configured (${connection.protocol}, token omitted)`);
  } catch (error) {
    connection = null;
    elements.connection.textContent = error.message;
    elements.endpoint.textContent = "Not configured";
    record(`Configuration rejected: ${error.message}`);
  }
  updateControls();
});

async function acquireWakeLock() {
  if (!("wakeLock" in navigator)) throw new Error("Screen Wake Lock API is unavailable in this context.");
  if (document.visibilityState !== "visible") throw new Error("App must be visible to request a wake lock.");
  if (wakeSentinel && !wakeSentinel.released) return;
  const sentinel = await navigator.wakeLock.request("screen");
  wakeSentinel = sentinel;
  sentinel.addEventListener("release", () => {
    if (wakeSentinel === sentinel) wakeSentinel = null;
    elements.wake.textContent = sessionWanted
      ? "Wake lock released by the browser; will try again when visible"
      : "Wake lock inactive";
    record("Wake lock released");
  });
  elements.wake.textContent = "Wake lock active while this app remains visible";
  record("Wake lock acquired");
}

elements.start.addEventListener("click", async () => {
  sessionWanted = true;
  elements.start.disabled = true;
  elements.end.disabled = false;
  try {
    await acquireWakeLock();
  } catch (error) {
    elements.wake.textContent = `Wake lock unavailable: ${error.name}: ${error.message}`;
    record(`Wake lock request failed: ${error.name}: ${error.message}`);
  }
});

elements.end.addEventListener("click", async () => {
  sessionWanted = false;
  const sentinel = wakeSentinel;
  wakeSentinel = null;
  if (sentinel && !sentinel.released) await sentinel.release();
  elements.start.disabled = false;
  elements.end.disabled = true;
  elements.wake.textContent = "Wake lock inactive";
  record("Foreground session ended by user");
});

document.addEventListener("visibilitychange", async () => {
  updateDiagnostics();
  record(`Visibility changed to ${document.visibilityState}`);
  if (document.visibilityState === "visible" && sessionWanted && (!wakeSentinel || wakeSentinel.released)) {
    try {
      await acquireWakeLock();
    } catch (error) {
      elements.wake.textContent = `Wake lock unavailable: ${error.name}: ${error.message}`;
      record(`Wake lock reacquisition failed: ${error.name}: ${error.message}`);
    }
  }
});

async function sendCommand(command) {
  if (!connection || requestPending) return;
  requestPending = true;
  updateControls();
  elements.command.textContent = `Sending ${command} once…`;
  const started = performance.now();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 3000);
  try {
    const response = await fetch(`${connection.baseUrl}/${command}`, {
      method: "POST",
      headers: {Authorization: `Bearer ${connection.token}`},
      body: null,
      cache: "no-store",
      credentials: "omit",
      signal: controller.signal,
    });
    const body = (await response.text()).trim();
    const elapsed = Math.round(performance.now() - started);
    if (response.status === 202) {
      elements.command.textContent = `${command} accepted in ${elapsed} ms. Confirm the visible page change.`;
      record(`${command} received HTTP 202 in ${elapsed} ms`);
    } else {
      elements.command.textContent = `${command} was not accepted: HTTP ${response.status}${body ? ` — ${body}` : ""}`;
      record(`${command} received HTTP ${response.status} in ${elapsed} ms`);
    }
  } catch (error) {
    const elapsed = Math.round(performance.now() - started);
    const detail = error.name === "AbortError" ? "timed out" : `${error.name}: ${error.message}`;
    elements.command.textContent = `Uncertain result: ${command} ${detail} after ${elapsed} ms. Check the Kindle. This app will not retry.`;
    record(`${command} fetch failed after ${elapsed} ms: ${detail}`);
  } finally {
    clearTimeout(timeout);
    requestPending = false;
    updateControls();
  }
}

elements.next.addEventListener("click", () => sendCommand("next"));
elements.back.addEventListener("click", () => sendCommand("back"));

elements.copy.addEventListener("click", async () => {
  const lines = [
    `Recorded: ${new Date().toISOString()}`,
    `User agent: ${navigator.userAgent}`,
    `Frontend origin: ${location.origin}`,
    `Secure context: ${window.isSecureContext}`,
    `Display mode: ${displayMode()}`,
    `Visibility: ${document.visibilityState}`,
    `Wake Lock API: ${"wakeLock" in navigator}`,
    `Service worker: ${"serviceWorker" in navigator}`,
    `Endpoint: ${connection ? connection.baseUrl : "not configured"}`,
    `Wake state: ${elements.wake.textContent}`,
    `Last event: ${elements.event.textContent}`,
  ];
  try {
    await navigator.clipboard.writeText(lines.join("\n"));
    record("Diagnostics copied (token omitted)");
  } catch (error) {
    record(`Diagnostics copy failed: ${error.name}: ${error.message}`);
  }
});

async function registerWorker() {
  if (!("serviceWorker" in navigator)) return;
  try {
    const registration = await navigator.serviceWorker.register("service-worker.js");
    elements.worker.textContent = `registered (${registration.scope})`;
    record("Service worker registered");
  } catch (error) {
    elements.worker.textContent = `registration failed: ${error.name}`;
    record(`Service worker registration failed: ${error.name}: ${error.message}`);
  }
}

updateDiagnostics();
updateControls();
registerWorker();
