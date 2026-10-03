import { parseConnection, consumePairingFragment } from "./pairing.js";
import { VoiceSession } from "./voice-session.js";
import { ACTIVE_DETECTOR } from "./detector-config.js";

const $ = (id) => document.getElementById(id);

const elements = {
  form: $("connection-form"), endpointInput: $("endpoint-input"),
  token: $("token"), connection: $("connection-state"),
  dialog: $("connection-dialog"), manual: $("manual-connection"),
  cancel: $("cancel-connection"), retry: $("retry-connection"),
  start: $("start-session"), end: $("end-session"), wake: $("wake-state"),
  wakeOnly: $("wake-only"),
  listening: $("listening-state"), toast: $("voice-toast"),
  testControls: $("voice-test-controls"), testNext: $("test-next"),
  testBack: $("test-back"), testSleep: $("test-sleep"),
  next: $("next"), back: $("back"), command: $("command-state"),
  origin: $("diag-origin"), secure: $("diag-secure"), display: $("diag-display"),
  visibility: $("diag-visibility"), wakeApi: $("diag-wake-api"),
  audio: $("diag-audio"),
  worker: $("diag-worker"),
  endpoint: $("diag-endpoint"), event: $("diag-event"),
  copy: $("copy-diagnostics"),
};

let connection = null;
let wakeSentinel = null;
let sessionWanted = false;
let requestPending = false;
let connectionVerified = false;
let connectionCheck = null;
let voice = null;
let voiceEpoch = 0;
let toastTimer = null;
let lastDetection = {command: null, at: 0};
const testMode = ["localhost", "127.0.0.1"].includes(location.hostname)
  && new URLSearchParams(location.search).get("voice-test") === "1";
elements.testControls.hidden = !testMode;

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

function toast(message) {
  clearTimeout(toastTimer);
  elements.toast.textContent = message;
  elements.toast.hidden = false;
  toastTimer = setTimeout(() => { elements.toast.hidden = true; }, 3000);
}

function detected(command, epoch) {
  if (epoch !== voiceEpoch || !sessionWanted || document.visibilityState !== "visible"
    || !["next", "back", "sleep"].includes(command)) return;
  const now = performance.now();
  if (lastDetection.command === command && now - lastDetection.at < 800) return;
  lastDetection = {command, at: now};
  toast(`Heard ${command}`);
  // Share the manual sender's verification, in-flight and no-retry guards.
  // Sleep remains detection-only; blocked turns are dropped, never queued.
  if (command === "next" || command === "back") void sendCommand(command);
}

function updateControls() {
  const enabled = Boolean(connection) && connectionVerified && !requestPending;
  elements.next.disabled = !enabled;
  elements.back.disabled = !enabled;
  elements.retry.hidden = !connection || connectionVerified;
  elements.retry.disabled = Boolean(connectionCheck) || requestPending;
}

function updateDiagnostics() {
  elements.origin.textContent = location.origin;
  elements.secure.textContent = window.isSecureContext ? "yes" : "no";
  elements.display.textContent = displayMode();
  elements.visibility.textContent = document.visibilityState;
  elements.wakeApi.textContent = "wakeLock" in navigator ? "available" : "unavailable";
  elements.worker.textContent = "serviceWorker" in navigator ? "available" : "unavailable";
}

function connectionStatus(state, message) {
  elements.connection.dataset.state = state;
  elements.connection.textContent = message;
}

function resetConnection() {
  connectionCheck?.abort();
  connectionCheck = null;
  connection = null;
  connectionVerified = false;
  elements.endpoint.textContent = "Not configured";
  elements.command.textContent = "Connect to the Kindle before sending a command.";
  updateControls();
}

async function verifyConnection() {
  if (!connection) return;
  connectionCheck?.abort();
  const candidate = connection;
  const controller = new AbortController();
  connectionCheck = controller;
  connectionVerified = false;
  connectionStatus("checking", `Checking connection to ${candidate.baseUrl}…`);
  updateControls();
  const timeout = setTimeout(() => controller.abort(), 3000);
  try {
    const response = await fetch(`${candidate.baseUrl}/connect`, {
      method: "POST",
      headers: {Authorization: `Bearer ${candidate.token}`},
      body: null,
      cache: "no-store",
      credentials: "omit",
      redirect: "error",
      referrerPolicy: "no-referrer",
      signal: controller.signal,
    });
    if (connectionCheck !== controller) return;
    if (response.status === 204) {
      connectionVerified = true;
      connectionStatus("success", `Connected to ${candidate.baseUrl}`);
      elements.command.textContent = "Close the Kindle QR and menus before using Next or Back. No page-turn command was sent.";
      record("Connection check succeeded (HTTP 204, token omitted)");
    } else {
      const detail = response.status === 401
        ? "Authentication rejected. Scan the current Kindle code or re-enter the token."
        : response.status === 404
          ? "Update the Kindle plugin to support connection checks."
          : `HTTP ${response.status}. Check the Kindle listener and network.`;
      connectionStatus("failed", `Connection failed: ${detail}`);
      record(`Connection check failed (HTTP ${response.status})`);
    }
  } catch {
    if (connectionCheck !== controller) return;
    // Never echo arbitrary fetch errors: they can contain URLs/credentials.
    connectionStatus("failed", controller.signal.aborted
      ? "Connection failed: timed out. Check the Kindle and network, then retry."
      : "Connection failed: unreachable or blocked by the browser. Check the Kindle, Wi-Fi/Tailscale and network permissions, then retry.");
    record(controller.signal.aborted ? "Connection check timed out" : "Connection check network failure");
  } finally {
    clearTimeout(timeout);
    if (connectionCheck === controller) {
      connectionCheck = null;
      updateControls();
    }
  }
}

function useConnection(nextConnection, source) {
  resetConnection();
  connection = nextConnection;
  elements.endpointInput.value = connection.baseUrl;
  elements.token.value = "";
  elements.endpoint.textContent = connection.baseUrl;
  record(`Connection configured from ${source} (${connection.transport}, ${connection.protocol}, token omitted)`);
  verifyConnection();
}

function acceptPairingLink() {
  try {
    const paired = consumePairingFragment(location, history);
    if (paired) {
      if (elements.dialog.open) elements.dialog.close();
      useConnection(paired, "pairing link");
    }
  } catch {
    resetConnection();
    connectionStatus("failed", "Invalid pairing link. Scan the current Kindle code or enter the connection manually.");
    record("Pairing link rejected (credentials omitted)");
  }
}

elements.manual.addEventListener("click", () => {
  elements.endpointInput.value = connection?.baseUrl || "";
  elements.token.value = "";
  elements.dialog.showModal();
});
elements.cancel.addEventListener("click", () => elements.dialog.close());
elements.dialog.addEventListener("close", () => {
  elements.token.value = "";
  elements.manual.focus();
});
elements.dialog.addEventListener("cancel", () => { elements.token.value = ""; });
elements.form.addEventListener("submit", (event) => {
  event.preventDefault();
  let candidate;
  let errorMessage;
  try {
    candidate = parseConnection(elements.endpointInput.value, elements.token.value);
  } catch (error) {
    errorMessage = error.message; // validation messages are fixed, never input
  }
  elements.token.value = "";
  elements.dialog.close();
  if (candidate) useConnection(candidate, "manual entry");
  else {
    resetConnection();
    connectionStatus("failed", `Connection failed: ${errorMessage}`);
    record("Manual connection rejected (credentials omitted)");
  }
});
elements.retry.addEventListener("click", verifyConnection);
window.addEventListener("hashchange", acceptPairingLink);

async function acquireWakeLock() {
  if (!("wakeLock" in navigator)) throw new Error("Screen Wake Lock API is unavailable in this context.");
  if (document.visibilityState !== "visible") throw new Error("App must be visible to request a wake lock.");
  if (wakeSentinel && !wakeSentinel.released) return wakeSentinel;
  const sentinel = await navigator.wakeLock.request("screen");
  wakeSentinel = sentinel;
  sentinel.addEventListener("release", () => {
    if (wakeSentinel !== sentinel) return;
    wakeSentinel = null;
    elements.wake.textContent = sessionWanted
      ? "Wake lock released by the browser; will try again when visible"
      : "Wake lock inactive";
    record("Wake lock released");
  });
  elements.wake.textContent = "Wake lock active while this app remains visible";
  record("Wake lock acquired");
  return sentinel;
}

async function stopListening() {
  voiceEpoch++;
  sessionWanted = false;
  elements.end.disabled = true;
  const previous = voice;
  voice = null;
  const sentinel = wakeSentinel;
  wakeSentinel = null;
  try {
    await previous?.stop();
  } finally {
    if (sentinel && !sentinel.released) await sentinel.release();
    elements.start.disabled = false;
    elements.wake.textContent = "Wake lock inactive";
    elements.listening.textContent = "Microphone off";
    elements.audio.textContent = "Not listening";
  }
}

elements.start.addEventListener("click", async () => {
  if (sessionWanted) return;
  sessionWanted = true;
  elements.wakeOnly.hidden = true;
  lastDetection = {command: null, at: 0};
  const epoch = ++voiceEpoch;
  elements.start.disabled = true;
  elements.end.disabled = false;
  elements.listening.textContent = "Starting microphone and detector…";
  elements.audio.textContent = "Starting…";
  voice = new VoiceSession({
    onCommand: (command) => detected(command, epoch),
    onMetrics: (metrics) => {
      if (epoch !== voiceEpoch) return;
      elements.audio.textContent = `${metrics.processed} chunks forwarded, ${metrics.dropped} dropped; `
        + `max bridge ${Math.round(metrics.maxProcessingMs)} ms, max delivery→ack ${Math.round(metrics.maxQueueMs)} ms`
        + (ACTIVE_DETECTOR === "vosk" ? " (Vosk's inner decoder is not measured)" : "");
    },
    onState: (message) => {
      if (epoch !== voiceEpoch) return;
      void stopListening().then(() => { elements.listening.textContent = message; });
    },
  });
  try {
    const acquired = await acquireWakeLock();
    if (epoch !== voiceEpoch) {
      if (wakeSentinel === acquired) wakeSentinel = null;
      if (acquired && !acquired.released) await acquired.release();
      if (!wakeSentinel) elements.wake.textContent = "Wake lock inactive";
      return;
    }
    const ready = await voice.start(testMode ? "test" : ACTIVE_DETECTOR);
    if (epoch !== voiceEpoch || !ready) return;
    elements.listening.textContent = testMode ? "Test detector listening (simulated commands)"
      : `Microphone listening (${ACTIVE_DETECTOR})`;
    toast(testMode ? "Test listening started (simulated)" : "Listening started");
  } catch (error) {
    if (epoch !== voiceEpoch) return;
    await stopListening();
    elements.listening.textContent = `Listening unavailable: ${error.message}`;
    elements.wakeOnly.hidden = false; // Preserve the previous wake-lock-only capability if the model cannot load.
    record(`Listening could not start (${error.name || "Error"})`);
  }
});

elements.end.addEventListener("click", async () => {
  await stopListening();
  record("Listening stopped by user");
});

elements.wakeOnly.addEventListener("click", async () => {
  if (sessionWanted) return;
  sessionWanted = true;
  const epoch = ++voiceEpoch;
  elements.start.disabled = true;
  elements.end.disabled = false;
  try {
    const acquired = await acquireWakeLock();
    if (epoch !== voiceEpoch) {
      if (wakeSentinel === acquired) wakeSentinel = null;
      if (acquired && !acquired.released) await acquired.release();
      if (!wakeSentinel) elements.wake.textContent = "Wake lock inactive";
      return;
    }
    elements.listening.textContent = "Microphone off; screen wake lock only";
  } catch {
    if (epoch !== voiceEpoch) return;
    await stopListening();
    elements.listening.textContent = "Wake lock unavailable";
  }
});

for (const [element, command] of [[elements.testNext, "next"], [elements.testBack, "back"], [elements.testSleep, "sleep"]]) {
  element.addEventListener("click", () => { if (testMode && sessionWanted) voice?.simulate(command); });
}

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
  if (!connection || !connectionVerified || requestPending) return;
  const candidate = connection;
  requestPending = true;
  updateControls();
  elements.command.textContent = `Sending ${command} once…`;
  const started = performance.now();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 3000);
  try {
    const response = await fetch(`${candidate.baseUrl}/${command}`, {
      method: "POST",
      headers: {Authorization: `Bearer ${candidate.token}`},
      redirect: "error",
      referrerPolicy: "no-referrer",
      body: null,
      cache: "no-store",
      credentials: "omit",
      signal: controller.signal,
    });
    const body = (await response.text()).trim();
    const elapsed = Math.round(performance.now() - started);
    if (connection !== candidate) return;
    if (response.status === 202) {
      elements.command.textContent = `${command} accepted in ${elapsed} ms. Confirm the visible page change.`;
      record(`${command} received HTTP 202 in ${elapsed} ms`);
    } else {
      elements.command.textContent = `${command} was not accepted: HTTP ${response.status}${body ? ` — ${body}` : ""}`;
      record(`${command} received HTTP ${response.status} in ${elapsed} ms`);
    }
  } catch (error) {
    if (connection !== candidate) return;
    const elapsed = Math.round(performance.now() - started);
    const detail = error.name === "AbortError" ? "timed out" : "failed to reach the Kindle";
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
    `Audio processing: ${elements.audio.textContent}`,
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

acceptPairingLink();
updateDiagnostics();
updateControls();
registerWorker();
