// sherpa-onnx bridge for a self-hosted single-thread WASM KWS build.
// See README for the required pinned vendor build and English BPE keyword assets.
export async function createDetector(emit) {
  let runtime;
  try {
    runtime = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("sherpa-onnx initialization timed out.")), 20000);
      self.Module = {
        locateFile(path) { return new URL(`./vendor/sherpa-onnx/${path}`, self.location.href).href; },
        onRuntimeInitialized() { clearTimeout(timer); resolve(self.Module); },
        onAbort(reason) { clearTimeout(timer); reject(new Error(`sherpa-onnx WASM initialization failed: ${String(reason)}`)); },
      };
      try {
        importScripts("./vendor/sherpa-onnx/sherpa-onnx-kws.js", "./vendor/sherpa-onnx/sherpa-onnx-wasm-kws-main.js");
      } catch {
        clearTimeout(timer);
        reject(new Error("sherpa-onnx WASM/model assets are not installed."));
      }
    });
    const response = await fetch("./vendor/sherpa-onnx/keywords.txt", {cache: "no-store"});
    if (!response.ok) throw new Error("Keyword configuration is missing.");
    const keywords = await response.text();
    if (!keywords.trim()) throw new Error("Keyword configuration is empty.");
    const recognizer = self.createKws(runtime, {
      featConfig: {samplingRate: 16000, featureDim: 80},
      modelConfig: {
        transducer: {
          encoder: "/encoder.onnx", decoder: "/decoder.onnx", joiner: "/joiner.onnx",
        },
        tokens: "/tokens.txt", provider: "cpu", numThreads: 1,
        debug: 0, modelingUnit: "bpe", bpeVocab: "/bpe.model",
      },
      maxActivePaths: 4, numTrailingBlanks: 1,
      keywordsScore: 1, keywordsThreshold: 0.25,
      keywords: keywords.trim(),
    });
    if (!recognizer.handle) throw new Error("sherpa-onnx could not create a keyword spotter.");
    const stream = recognizer.createStream();
    if (!stream.handle) throw new Error("sherpa-onnx could not create a keyword stream.");
    // Maintain resampling phase across incoming AudioWorklet chunks; no whole-session audio.
    let phase = 1;
    let last = 0;
    return {
      accept(samples, inputRate) {
        let pcm = samples;
        if (inputRate !== 16000) {
          const ratio = inputRate / 16000;
          const out = [];
          while (phase < samples.length) {
            const i = Math.floor(phase);
            const frac = phase - i;
            out.push((i ? samples[i - 1] : last) * (1 - frac) + samples[i] * frac);
            phase += ratio;
          }
          phase -= samples.length;
          last = samples[samples.length - 1];
          pcm = Float32Array.from(out);
        }
        if (!pcm.length) return;
        stream.acceptWaveform(16000, pcm);
        while (recognizer.isReady(stream)) {
          recognizer.decode(stream);
          const keyword = recognizer.getResult(stream).keyword?.trim().toLowerCase();
          if (["next", "back", "sleep"].includes(keyword)) {
            emit(keyword);
            recognizer.reset(stream);
            break;
          }
        }
      },
    };
  } catch (error) {
    throw new Error(error.message || "sherpa-onnx could not start.");
  }
}
