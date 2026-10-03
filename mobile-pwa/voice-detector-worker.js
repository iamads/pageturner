// Detector implementations receive PCM only; they never receive pairing credentials.
let detector = null;
let sessionId = null;
let simulated = false;
const allowed = new Set(["next", "back", "sleep"]);

self.onmessage = async ({data}) => {
  if (data.type === "init") {
    sessionId = data.sessionId;
    try {
      simulated = data.mode === "test" && ["localhost", "127.0.0.1"].includes(self.location.hostname);
      if (data.mode === "test" && !simulated) throw new Error("Test mode is available only on localhost.");
      if (!simulated) {
        if (!["sherpa", "vosk"].includes(data.mode)) throw new Error("Unknown detector selection.");
        const {createDetector} = await import(data.mode === "vosk" ? "./vosk-detector.js" : "./sherpa-detector.js");
        detector = await createDetector((command) => {
          if (allowed.has(command)) self.postMessage({type: "detection", sessionId, command, detectedAt: Date.now()});
        }, (message) => self.postMessage({type: "error", sessionId, message}));
      }
      self.postMessage({type: "ready", sessionId});
    } catch (error) {
      self.postMessage({type: "error", sessionId, message: error.message || "Model could not load."});
    }
    return;
  }
  if (data.sessionId !== sessionId) return;
  if (data.type === "simulate" && simulated && allowed.has(data.command)) {
    self.postMessage({type: "detection", sessionId, command: data.command, detectedAt: Date.now()});
  }
  if (data.type !== "audio") return;
  const started = performance.now();
  try {
    if (!(data.samples instanceof Float32Array) || data.samples.length > 8192
      || !Number.isFinite(data.sampleRate) || data.sampleRate < 8000 || data.sampleRate > 192000) return;
    if (detector) detector.accept(data.samples, data.sampleRate);
  } catch {
    self.postMessage({type: "error", sessionId, message: "Detector failed while processing audio."});
  } finally {
    self.postMessage({type: "ack", sessionId, capturedAt: data.capturedAt,
      processingMs: performance.now() - started});
  }
};
