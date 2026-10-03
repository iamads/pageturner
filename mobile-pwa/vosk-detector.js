// Offline small-vocabulary ASR alternative to sherpa KWS. The bundled
// vosk-browser runtime spawns its own WASM Worker; the model is same-origin.
const commands = new Set(["next", "back", "sleep"]);

export function exactCommand(text) {
  const candidate = typeof text === "string" ? text.trim().toLowerCase() : "";
  return commands.has(candidate) ? candidate : null;
}

export async function createDetector(emit, fail = () => {}) {
  importScripts("./vendor/vosk/vosk.js");
  if (!self.Vosk?.createModel) throw new Error("Local Vosk runtime is unavailable.");
  // Absolute URL is necessary: vosk-browser's own Worker can be a blob URL.
  const modelUrl = new URL("./vendor/vosk/model.tar.gz", self.location.href).href;
  let model;
  try {
    model = await self.Vosk.createModel(modelUrl, -1);
  } catch {
    throw new Error("Local Vosk model could not load.");
  }
  model.on("error", () => fail("Vosk model failed."));
  let recognizer = null;
  let rate = null;
  return {
    accept(samples, sampleRate) {
      if (!recognizer) {
        rate = sampleRate;
        // [unk] keeps the grammar from forcing all unrelated speech to a command.
        recognizer = new model.KaldiRecognizer(rate, JSON.stringify(["next", "back", "sleep", "[unk]"]));
        recognizer.on("error", () => fail("Vosk recognizer failed."));
        // Partial transcripts fluctuate; only completed, exact bare words are events.
        recognizer.on("result", (message) => {
          const command = exactCommand(message?.result?.text);
          if (command) emit(command);
        });
      }
      if (sampleRate !== rate) throw new Error("Capture sample rate changed during the session.");
      recognizer.acceptWaveformFloat(samples, rate);
    },
    dispose() {
      recognizer?.remove();
      model.terminate();
    },
  };
}
