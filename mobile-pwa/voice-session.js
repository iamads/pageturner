// Stable audio-in / command-event-out boundary. Model-specific work stays in the Worker.
const commands = new Set(["next", "back", "sleep"]);

export function validDetection(event, sessionId) {
  return event?.type === "detection" && event.sessionId === sessionId
    && commands.has(event.command);
}

export class VoiceSession {
  constructor({onCommand, onState, onMetrics = () => {}}) {
    this.onCommand = onCommand;
    this.onState = onState;
    this.onMetrics = onMetrics;
    this.generation = 0;
    this.resources = null;
  }

  async start(mode = "sherpa") {
    if (this.resources) throw new Error("Listening is already starting or active.");
    const sessionId = ++this.generation;
    const resources = {
      stream: null, context: null, worker: null, source: null, node: null, sink: null,
      pending: 0, processed: 0, dropped: 0, maxProcessingMs: 0, maxQueueMs: 0,
      metricsAt: 0, cancelReady: null,
    };
    this.resources = resources;
    const current = () => this.resources === resources && this.generation === sessionId;
    try {
      if (!navigator.mediaDevices?.getUserMedia || !window.AudioWorkletNode) {
        throw new Error("Microphone or AudioWorklet is unavailable in this browser.");
      }
      // Request on the button gesture, before waiting for model/asset loading.
      resources.stream = await navigator.mediaDevices.getUserMedia({audio: {channelCount: 1}, video: false});
      if (!current()) { resources.stream.getTracks().forEach((track) => track.stop()); return false; }
      // Let the browser do the high-quality conversion when it supports 16 kHz.
      // The detector still accepts the actual context rate if it does not.
      try { resources.context = new AudioContext({sampleRate: 16000}); }
      catch { resources.context = new AudioContext(); }
      await resources.context.audioWorklet.addModule("voice-capture-worklet.js");
      if (!current()) return false;
      resources.worker = new Worker("voice-detector-worker.js");
      await new Promise((resolve, reject) => {
        let ready = false;
        const timer = setTimeout(() => fail(new Error("Detector startup timed out.")), mode === "vosk" ? 120000 : 30000);
        const fail = (error) => {
          if (!ready) { clearTimeout(timer); reject(error); }
          else if (current()) this.onState("Detector stopped. Stop and start listening again.");
        };
        resources.cancelReady = () => { clearTimeout(timer); reject(new Error("Listening stopped.")); };
        resources.worker.onmessage = ({data}) => {
          if (!current() || data.sessionId !== sessionId) return;
          if (data.type === "ready") { ready = true; clearTimeout(timer); resources.cancelReady = null; resolve(); }
          else if (data.type === "error") fail(new Error("Detector unavailable: " + data.message));
          else if (data.type === "ack") {
            resources.pending = Math.max(0, resources.pending - 1);
            resources.processed++;
            if (Number.isFinite(data.processingMs)) {
              resources.maxProcessingMs = Math.max(resources.maxProcessingMs, data.processingMs);
            }
            if (Number.isFinite(data.capturedAt)) {
              resources.maxQueueMs = Math.max(resources.maxQueueMs, Math.max(0, Date.now() - data.capturedAt));
            }
          }
          else if (validDetection(data, sessionId)) this.onCommand(data.command);
        };
        resources.worker.onerror = () => fail(new Error("Detector Worker failed."));
        resources.worker.postMessage({type: "init", mode, sessionId});
      });
      if (!current()) return false;
      resources.node = new AudioWorkletNode(resources.context, "voice-capture");
      resources.source = resources.context.createMediaStreamSource(resources.stream);
      resources.sink = resources.context.createGain();
      resources.sink.gain.value = 0; // Keeps the graph running without playing microphone audio.
      const maxPending = Math.max(4, Math.ceil(resources.context.sampleRate * 0.4 / 1024)); // ≤~400 ms of audio.
      resources.node.port.onmessage = ({data}) => {
        if (!current() || !(data instanceof Float32Array)) return;
        if (resources.pending >= maxPending) resources.dropped++;
        else {
          resources.pending++;
          resources.worker.postMessage({type: "audio", sessionId, capturedAt: Date.now(), sampleRate: resources.context.sampleRate, samples: data}, [data.buffer]);
        }
        const now = performance.now();
        if (now - resources.metricsAt > 1000) {
          resources.metricsAt = now;
          this.onMetrics({processed: resources.processed, dropped: resources.dropped,
            maxProcessingMs: resources.maxProcessingMs, maxQueueMs: resources.maxQueueMs});
        }
      };
      resources.stream.getAudioTracks().forEach((track) => {
        track.addEventListener("ended", () => { if (current()) this.onState("Microphone ended. Stop and start listening again."); });
      });
      resources.source.connect(resources.node);
      resources.node.connect(resources.sink);
      resources.sink.connect(resources.context.destination);
      await resources.context.resume();
      if (!current()) return false;
      return true;
    } catch (error) {
      if (current()) await this.stop();
      throw error;
    }
  }

  // Only available when the controller explicitly enables localhost test mode.
  simulate(command) {
    if (commands.has(command)) this.resources?.worker?.postMessage({type: "simulate", sessionId: this.generation, command});
  }

  async stop() {
    this.generation++;
    const r = this.resources;
    this.resources = null;
    if (!r) return;
    r.cancelReady?.();
    if (r.node?.port) r.node.port.onmessage = null;
    r.node?.disconnect();
    r.source?.disconnect();
    r.sink?.disconnect();
    r.worker?.terminate();
    r.stream?.getTracks().forEach((track) => track.stop());
    if (r.context && r.context.state !== "closed") await r.context.close();
  }
}
