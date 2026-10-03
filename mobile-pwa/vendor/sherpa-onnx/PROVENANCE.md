# Bundled keyword spotter provenance

- Runtime: [`k2-fsa/sherpa-onnx` v1.13.8](https://github.com/k2-fsa/sherpa-onnx/tree/v1.13.8), commit `11afbd009a7f8c08f4bcf2fc1b265d0df4670fbf`, Apache-2.0 (see `LICENSE`). Vendored `sherpa-onnx-kws.js` comes from `wasm/kws/` at that tag.
- Acoustic model: [`sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01`](https://github.com/k2-fsa/sherpa-onnx/releases/tag/kws-models), publisher's archive declares Apache License 2.0 in its README. Archive SHA-256: `f170013b4716e41b62b9bfd809687c207cef798ef9bc6534d524e17af9b6561a`. Only INT8 encoder/decoder/joiner, tokens and BPE model were preloaded. Archive includes the publisher's original license metadata.
- Build: Emscripten 4.0.23, upstream `build-wasm-simd-kws.sh`; upstream demo CMake filename check changed to `decoder.onnx`, initial memory reduced from 512 MB to **256 MB** with memory growth enabled. Single-thread WASM SIMD, not a SharedArrayBuffer or cloud service. Built on macOS arm64; not yet tested on iPhone.
- Keyword text: `keywords_raw.txt` → SentencePiece 0.2.1 using this exact model's `bpe.model`; emitted three bare words with `@next`, `@back`, `@sleep` labels. Tokens validated against `tokens.txt`. `keywords.txt` can be edited/recalibrated without recompiling the model, but all operating-point changes need re-evaluation.
- Rebuild: `tools/build-sherpa-kws.sh` from repository root after sourcing an Emscripten 4.0.23 environment and installing Python sentencepiece. It checks the upstream model archive checksum and regenerates all binaries/keywords.

| Asset | SHA-256 |
|---|---|
| `sherpa-onnx-kws.js` | `03b44e372795fd907e84eecd29419e1d052dc6704ac06935c9bf9fe19b3e3434` |
| `sherpa-onnx-wasm-kws-main.js` | `6d8cbfd2868d65621340b053d6337d82d801b9c4e7b3e0da4f1682ee6412477f` |
| `sherpa-onnx-wasm-kws-main.wasm` | `3e72583b9535ebe99f126f9c2daf62307eeb2ef7a328341aac08b2b766b5694d` |
| `sherpa-onnx-wasm-kws-main.data` | `a2ac267c52f314c76cdf81663543abdbf4cc2bc5b84084c47c47aa6cd451c99e` |
| `keywords.txt` | `09209490277b5a3ae6449739833ddd43a1d9d2d10a15892c8b1f7bd2633250a0` |

**Local validation:** Chrome headless loaded the bundled WASM/model in the Worker and decoded PCM; the installed v6 service worker also loaded the detector while Chrome network emulation was offline. With a *temporary* `HELLO WORLD` keyword labeled `next`, synthesized “hello world” emitted one event, proving the streaming/WASM bridge. The checked-in keyword file was restored to only the three requested commands. Synthesized single-word “sleep” triggered, but “next” and “back” did not at the initial threshold; synthetic speech does not predict real-user accuracy. No microphone/iPhone, long-session, battery or false-activation testing has been performed.
