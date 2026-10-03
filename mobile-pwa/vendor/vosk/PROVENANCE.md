# Experimental Vosk detector assets

- Browser runtime: [`vosk-browser` 0.0.8](https://www.npmjs.com/package/vosk-browser), Apache-2.0; `vosk.js` extracted from its npm `dist/` tarball. See `COPYING`. Its bundle also contains third-party code, including UUID (MIT); preserve upstream notices on redistribution.
- English model: [`vosk-model-small-en-us-0.15.zip`](https://alphacephei.com/vosk/models/vosk-model-small-en-us-0.15.zip), listed as Apache 2.0 by the publisher in the [model catalog](https://alphacephei.com/vosk/models). Original ZIP SHA-256: `30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498`. Original model `README` is retained inside the packaged archive.
- Packaging: extracted the original ZIP, renamed its top-level directory `vosk-model-small-en-us-0.15/` to `model/` (required by `vosk-browser`), then made `model.tar.gz`. No acoustic model weights or configuration were changed.

| Asset | SHA-256 |
|---|---|
| `vosk.js` | `29504515526e974f4cb053cf08811c4de5fb2a74007c0a5a957db50eaa8d5d0c` |
| `model.tar.gz` | `c4fc8118322ba031d1442cf8c71d9d693da70ef9343a344c4855e8d3c753370c` |

The model is approximately **39 MB compressed**, downloaded from the same-origin PWA only when the code selects Vosk. Its browser wrapper may persist the model in IndexedDB/IDBFS; this is *model storage*, not microphone recording. The bundled runtime also occupies about 5.8 MB. Vosk's decoder runs in a nested Worker, so Page Turner's outer Worker timings do **not** measure the internal decoder time or queue. Final, exact-word results only are emitted, with `[unk]` in the grammar to allow rejection; partial transcripts never trigger commands.

**Local evidence:** in desktop headless Chrome, Vosk loaded the local model and emitted `next`, `back`, and `sleep` separately from synthesized utterances of those words. This is a functional wiring smoke test, **not** a user-voice accuracy, false-activation, latency, memory, or iPhone compatibility result. The normal code setting still selects sherpa until deliberately changed.
