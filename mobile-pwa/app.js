import { parseEndpoint } from "./endpoint.js";
import { parsePairingPayload } from "./pairing.js";

const $ = (id) => document.getElementById(id);

const elements = {
  form: $("connection-form"), endpointInput: $("endpoint-input"),
  token: $("token"), connection: $("connection-state"), scan: $("scan-qr"),
  scanner: $("scanner"), video: $("scanner-video"), canvas: $("scanner-canvas"),
  scannerState: $("scanner-state"), cancelScan: $("cancel-scan"),
  start: $("start-session"), end: $("end-session"), wake: $("wake-state"),
  next: $("next"), back: $("back"), command: $("command-state"),
  origin: $("diag-origin"), secure: $("diag-secure"), display: $("diag-display"),
  visibility: $("diag-visibility"), wakeApi: $("diag-wake-api"),
  cameraApi: $("diag-camera-api"), worker: $("diag-worker"),
  endpoint: $("diag-endpoint"), event: $("diag-event"),
  copy: $("copy-diagnostics"),
};

let connection = null;
let wakeSentinel = null;
let sessionWanted = false;
let requestPending = false;
let cameraStream = null;
let scanFrame = null;

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
  elements.cameraApi.textContent = navigator.mediaDevices?.getUserMedia ? "available" : "unavailable";
  elements.worker.textContent = "serviceWorker" in navigator ? "available" : "unavailable";
}

function parseConnection() {
  const endpoint = parseEndpoint(elements.endpointInput.value);
  const token = elements.token.value;
  if (!/^[A-Za-z0-9_-]{32,128}$/.test(token)) throw new Error("Enter the 32–128 character Page Turner token.");
  return {...endpoint, token};
}

function useConnection(nextConnection, source) {
  connection = nextConnection;
  elements.endpointInput.value = connection.baseUrl;
  elements.token.value = "";
  elements.connection.textContent = `Configured for ${connection.baseUrl}`;
  elements.endpoint.textContent = connection.baseUrl;
  record(`Connection configured from ${source} (${connection.transport}, ${connection.protocol}, token omitted)`);
  updateControls();
}

elements.form.addEventListener("submit", (event) => {
  event.preventDefault();
  try {
    useConnection(parseConnection(), "manual entry");
  } catch (error) {
    connection = null;
    elements.connection.textContent = error.message;
    elements.endpoint.textContent = "Not configured";
    record(`Configuration rejected: ${error.message}`);
    updateControls();
  }
});

function stopScanner() {
  if (scanFrame !== null) cancelAnimationFrame(scanFrame);
  scanFrame = null;
  if (cameraStream) cameraStream.getTracks().forEach((track) => track.stop());
  cameraStream = null;
  elements.video.srcObject = null;
  elements.scanner.hidden = true;
}

function scanVideoFrame() {
  if (!cameraStream) return;
  const video = elements.video;
  if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA && video.videoWidth > 0) {
    const scale = Math.min(1, 960 / video.videoWidth);
    const width = Math.max(1, Math.round(video.videoWidth * scale));
    const height = Math.max(1, Math.round(video.videoHeight * scale));
    const canvas = elements.canvas;
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d", {willReadFrequently: true});
    context.drawImage(video, 0, 0, width, height);
    const pixels = context.getImageData(0, 0, width, height);
    const result = window.jsQR(pixels.data, width, height, {inversionAttempts: "dontInvert"});
    if (result && result.data) {
      try {
        const paired = parsePairingPayload(result.data);
        stopScanner();
        useConnection(paired, "pairing QR");
        elements.command.textContent = "Pairing QR accepted. No command was sent.";
        return;
      } catch (error) {
        elements.scannerState.textContent = error.message;
      }
    }
  }
  scanFrame = requestAnimationFrame(scanVideoFrame);
}

async function startScanner() {
  if (!window.isSecureContext || !navigator.mediaDevices?.getUserMedia) {
    elements.connection.textContent = "Camera scanning requires a secure context and camera-capable browser.";
    record("QR scanner unavailable");
    return;
  }
  if (typeof window.jsQR !== "function") {
    elements.connection.textContent = "QR decoder failed to load; use manual entry.";
    record("QR decoder unavailable");
    return;
  }

  stopScanner();
  elements.scanner.hidden = false;
  elements.scannerState.textContent = "Requesting camera permission…";
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: false,
      video: {facingMode: {ideal: "environment"}},
    });
    if (document.visibilityState !== "visible") {
      stream.getTracks().forEach((track) => track.stop());
      throw new Error("Return to the visible app and try scanning again.");
    }
    cameraStream = stream;
    elements.video.srcObject = stream;
    await elements.video.play();
    elements.scannerState.textContent = "Point the camera at the Kindle QR code.";
    scanFrame = requestAnimationFrame(scanVideoFrame);
    record("QR scanner started (payload omitted)");
  } catch (error) {
    stopScanner();
    elements.connection.textContent = `Camera unavailable: ${error.name || "Error"}: ${error.message}`;
    record(`QR scanner failed: ${error.name || "Error"}: ${error.message}`);
  }
}

elements.scan.addEventListener("click", startScanner);
elements.cancelScan.addEventListener("click", () => {
  stopScanner();
  record("QR scanner cancelled");
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
  if (document.visibilityState !== "visible" && cameraStream) {
    stopScanner();
    record("QR scanner stopped because app became hidden");
  }
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

window.addEventListener("pagehide", stopScanner);

elements.copy.addEventListener("click", async () => {
  const lines = [
    `Recorded: ${new Date().toISOString()}`,
    `User agent: ${navigator.userAgent}`,
    `Frontend origin: ${location.origin}`,
    `Secure context: ${window.isSecureContext}`,
    `Display mode: ${displayMode()}`,
    `Visibility: ${document.visibilityState}`,
    `Wake Lock API: ${"wakeLock" in navigator}`,
    `Camera API: ${Boolean(navigator.mediaDevices?.getUserMedia)}`,
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
