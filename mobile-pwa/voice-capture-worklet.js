// Capture only; inference never runs on the audio rendering thread.
class VoiceCaptureProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.chunk = new Float32Array(1024);
    this.used = 0;
  }

  process(inputs, outputs) {
    const input = inputs[0];
    if (input?.length) {
      const frames = input[0].length;
      for (let i = 0; i < frames; i++) {
        let mono = 0;
        for (const channel of input) mono += channel[i] / input.length;
        this.chunk[this.used++] = mono;
        if (this.used === this.chunk.length) {
          this.port.postMessage(this.chunk, [this.chunk.buffer]);
          this.chunk = new Float32Array(1024);
          this.used = 0;
        }
      }
    }
    for (const output of outputs) for (const channel of output) channel.fill(0);
    return true;
  }
}
registerProcessor("voice-capture", VoiceCaptureProcessor);
