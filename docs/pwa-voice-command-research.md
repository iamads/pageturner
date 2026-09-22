# Continuous, free voice commands in the iPhone PWA

> Researched: 2026-09-21
> Status: Research and recommendation only. No microphone capture, voice model, API change, paid account, or deployment was implemented.
> Target: Owner's iPhone + KOReader Kindle, foreground installed PWA, small English command vocabulary, no paid speech service.
> Scope and assumptions: [Voice command specification](pwa-voice-command-spec.md).

## 1. Recommendation

There are two importantly different ways to satisfy the underlying goal:

1. **Least work overall: try Apple's built-in Voice Control operating the existing PWA buttons.** Say “Tap Next” or “Tap Back.” Apple performs recognition on the phone after the required language download; the resulting button activation invokes the existing API sender. No custom speech engine, speech-service subscription, or new native app is needed. This is an alternative to putting microphone recognition inside our JavaScript, not a claim that the PWA itself owns the listener. Validate it on the installed PWA before investing in an engine. [S1–S3]
2. **Best-fit free engine to investigate if recognition must live inside the PWA: streaming phrase spotting with `sherpa-onnx`, using its small English keyword-spotting model compiled for WebAssembly.** Detect complete phrases such as **“reader next”** and **“reader back”** directly. No cloud STT, per-command charge, runtime vendor account, separate wake-word model, or custom phrase-model training is needed. However, the existing browser demo is not production-ready: its memory settings and audio handling require changes and an iPhone feasibility test. [S8–S12]

For an embedded recognizer, choose **prefixed phrases, recognized as whole phrases by one engine**, rather than bare words or a two-stage “wake up, then speak” conversation. Ordinary conversation contains “next,” “back,” and “sleep” frequently. A prefix adds spoken time but should reduce accidental activations; this is an engineering hypothesis to validate, not a measured accuracy claim.

**Do not choose browser `SpeechRecognition`, Whisper, or a paid wake-word SDK as the default.** They either cannot guarantee local execution on the target Safari, do more work than three commands require, or fail the no-paid-service requirement.

These are recommendations for a bounded experiment, not a claim that a source comparison establishes the fastest or most accurate implementation on the owner's phone.

## 2. What “always listening” can mean in a PWA

### Achievable scope

After the user taps **Start listening**, grants microphone permission, and the model/audio context is ready, the visible PWA can continuously process microphone frames locally. Keep its foreground screen wake lock active, show real microphone/model state, and release the microphone on explicit Stop.

The user does not need to tap for every command. The initial tap/permission and later recovery taps are separate from continuous recognition.

### Not a reliable browser guarantee

An ordinary iPhone PWA cannot promise uninterrupted custom JavaScript recognition while the phone is locked, another app is foregrounded, a call takes the microphone, or iOS interrupts/suspends it. MDN specifically documents iOS Safari audio-context interruption when leaving the page or turning off the screen. A wake lock can be revoked and is not background execution permission. [S4–S7]

A Web Worker is useful for inference, but not a background-execution entitlement. A service worker is not a persistent microphone listener. Adding the PWA to the Home Screen does not grant native background-audio privileges. Do not use silent audio or similar workarounds as a supported design.

**Assumption used here:** continuous means during the foreground reading session, consistent with the existing product scope. If locked-phone custom listening becomes mandatory, this PWA architecture is not sufficient; that would require a separate OS/native integration decision.

## 3. What low latency actually requires

The expensive pattern to avoid is:

```text
record utterance → upload audio → cloud STT → returned transcript → Kindle API
```

The desired pattern is:

```text
microphone → streaming local detector → command event → Kindle API
```

Some recognition work necessarily happens before dispatch. “No STT round trip” is achievable; “act without first recognizing the command” is not. A local streaming recognizer may internally use speech-recognition techniques without sending audio away or generating an unrestricted transcript.

Measure these separately:

- Spoken phrase duration: longer phrases take longer to say.
- End of phrase → detector event: buffering, acoustic evidence, model compute, trailing silence/blanks, and scheduling.
- Detector event → API dispatch: validation and dispatch overhead.
- API dispatch → acknowledgement: HTTPS/Tailscale/network/plugin scheduling.
- Acknowledgement → visible e-ink turn: distinct from acceptance; HTTP 202 is not display completion.

A model processing frames every 20 or 80 ms does **not** establish 20 or 80 ms command latency. It can depend on a longer receptive field, decode chunk, or endpoint evidence. Keep the model loaded and warmed during the session; do not reload it per command.

**Proposed, not measured, initial target:** p95 end-of-phrase → detector event at or below 500 ms on the actual iPhone, with little additional application dispatch delay. Measure network and visible-turn latency separately. Tighten only after evidence; do not promise sub-100-ms end-to-end control.

## 4. Candidate comparison

| Approach | Local recognition? | Ongoing speech-service fee? | Effort for our commands | Main limitation | Recommendation |
|---|---|---|---|---|---|
| Apple Voice Control → PWA buttons | Apple documents offline use after setup | None additional | Very low for “Tap Next/Back”; custom phrases require settings | OS-owned listener, not PWA-owned; systemwide behavior | Try first for personal use |
| sherpa-onnx streaming keyword spotting | Yes, WASM | None; open-source runtime and publisher-labeled Apache-2.0 English model | Moderate integration/build; phrases need tokenization, not retraining | Browser demo needs memory/audio/lifecycle work; iPhone untested | Preferred embedded-engine spike |
| TensorFlow.js speech-commands | Yes, browser Web Audio/WebGL | None | Low with existing words; higher with exact new phrases | Defaults do not contain next/back/sleep/reader; training/generalization work | Strong fallback, especially personal calibration |
| Vosk-browser + constrained grammar | Yes, worker/WASM | None for suitable open-source model | Moderate; grammar simpler than training a classifier | Larger ASR model, final-result latency and unstable partials | Second embedded-engine option |
| openWakeWord | Local in supported runtimes | Code free; bundled model license restricted | Higher for custom phrases and browser port | Official browser example uses Python server; no official full JS pipeline | Not the lowest-effort PWA choice |
| microWakeWord / custom tiny neural KWS | Yes when integrated | No inherent service fee | High: data, training, DSP/runtime port, tuning | Designed primarily for embedded deployment, not turnkey browser use | Later optimization |
| Whisper via whisper.cpp/Transformers.js | Yes with local runtime/assets | None for appropriate model/license | Medium/high; much broader ASR than needed | More memory/compute, chunk/endpoint handling, hallucination risk | Avoid for three commands |
| Web Speech API `SpeechRecognition` | Browser-dependent; cannot force local in current Safari compatibility data | Usually no direct API bill | Very low demo effort | Local controls absent in Safari; continuous results are not an endless-session guarantee | Not a reliable offline foundation |
| Picovoice Porcupine/Rhino | On-device audio inference | Vendor licensing/account dependency | Low/moderate technically | Current FAQ describes enterprise trial, no dedicated personal plan | Exclude under no-paid-service constraint |
| Audio-volume/clap/whistle detector | Can be fully local | None | Low for a rough demonstration | Cannot understand words; nuisance/noise triggers and awkward command encoding | Not recommended for next/back/sleep |

Local recognition means audio need not leave the phone. It does not imply zero battery usage, zero first-load downloads, or offline Kindle control through the chosen networking setup.

## 5. Alternative with the least complication: iOS Voice Control

Apple explicitly documents:

- Offline use after the initial required download.
- Activating controls with **“Tap [item name]”**.
- “Show names” / “Show numbers” for discovering controls.
- Custom commands and recorded command playback.
- **Command mode**, which ignores non-command speech rather than dictating it into text fields.
- An **Attention Aware** setting on supported devices that can put listening to sleep when the user looks away. [S1–S3]

### Proposed trial

1. Establish working PWA button → Kindle HTTPS control first, or initially test only local UI activation.
2. In iPhone Settings → Accessibility → Voice Control, complete setup/language download.
3. Open the installed PWA, configure the endpoint/token, and start its foreground wake lock.
4. Use Command mode; finish editing the token/connection fields before testing.
5. Say **“Tap Next”**, then **“Tap Back.”** Use “Tap Back,” not “Go back,” which can navigate the interface.
6. If labels are ambiguous, use “Show names” and improve the buttons' accessible names. Prefer named activation over recorded screen-coordinate gestures, which break when layout changes.
7. If Attention Aware stops listening while looking at the Kindle, the owner can explicitly disable that Voice Control option for the trial.
8. Test normal reading posture, distance, quiet speech, accidental commands, and interaction with the PWA's disabled/pending buttons.

The current `Next` and `Back` buttons already call the shared one-shot HTTP sender. This approach reuses them without a custom audio stack. It does not require a Siri Shortcut or replacement native app, both previously rejected as the primary product architecture.

### Trade-offs

- Voice Control owns microphone/listening and recognition; our page cannot inspect confidence or guarantee that its own Start/Stop buttons control the OS listener.
- It is a broader system feature, not restricted to three commands. Review which commands are enabled; this is not a security boundary.
- Custom “reader next” mappings may use recorded commands, but require per-phone configuration and actual Home Screen-app testing. App-specific scoping may not distinguish a PWA as desired. Start with built-in “Tap…” commands rather than assuming custom mapping is frictionless.
- We have not tested this on the owner's installed PWA. Accessibility exposure and action speed must be verified.
- Do not run OS Voice Control and an independent PWA microphone recognizer simultaneously by default; microphone/audio-session interactions require separate testing.

**Conclusion:** if the goal is hands-free personal reading rather than owning recognition in JavaScript, this is the lowest-effort first experiment. If an integrated, portable PWA experience is required, use the embedded-engine path below.

## 6. Preferred embedded candidate: sherpa-onnx phrase spotting

### Why it matches the problem

The official documentation describes **open-vocabulary keyword spotting**: a small streaming ASR-like model with a decoder constrained to the configured keywords. It emits a selected phrase or no phrase. New keywords can be specified without retraining. Each phrase can have its own boosting score and trigger threshold. [S8]

Configure whole phrases:

```text
READER NEXT
READER BACK
READER SLEEP   # detection-only until its action is defined
```

Convert these to the English model's BPE tokens using the supplied tokenization tool **at build time**. The phone then uses the prebuilt keyword configuration. The developer may need Python/Emscripten locally for preparation, but the user does not run them while reading.

This is one streaming detector, not:

```text
wake-word model → wait for next utterance → second recognizer → parse transcript
```

That avoids an extra model and a wake/command timeout state machine. Recognize “reader next” spoken as one natural phrase; do not require a beep or pause between the words.

### Model and license evidence

- Runtime: `k2-fsa/sherpa-onnx`, Apache-2.0.
- English model: `sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01`.
- The model publisher's ModelScope metadata explicitly lists **Apache License 2.0**. This is model-specific evidence, not an inference from the runtime's license. Keep the publisher metadata and exact artifact provenance during packaging. [S9–S10]
- Official docs list approximately **4.6 MB encoder + 272 KB decoder + 160 KB joiner** for the INT8 files, excluding runtime, vocabulary, and packaging. FP32 files are larger.
- The release archive includes additional files; the whole English archive is about **17.6 MB compressed**. Do not confuse this with the approximately 5 MB selected INT8 weights or total runtime RAM.
- Whether INT8 actually improves browser latency needs benchmarking; smaller downloads do not guarantee faster WASM kernels.

No inference-service account, API key, or per-command fee is inherent in this configuration. Retain Apache notices and audit all redistributed runtime/model dependencies; this is not legal advice about training-data provenance.

### Important source-level findings: do not copy the demo unchanged

Inspected source revision: `1d04ac4d666430e911f526d9ae55a26a859159cd`.

1. `wasm/kws/` and `build-wasm-simd-kws.sh` demonstrate an actual browser/WASM keyword-spotting path. This is stronger evidence than assuming native or Node.js bindings work in a browser.
2. The demo defaults to **Chinese assets/keywords**. Our English model/configuration must replace them.
3. Its CMake configuration sets **`INITIAL_MEMORY=512MB`** plus a large stack. A 3.3-million-parameter model does not mean a tiny browser heap. Investigate a smaller measured configuration; reject this path if acceptable iPhone memory/thermal behavior cannot be achieved.
4. The demo uses deprecated **`ScriptProcessorNode`**, with a 4096-frame buffer, and performs decode work in the audio callback on the main thread. At its requested 16 kHz rate, that buffer alone spans 256 ms. It is not a low-latency production pipeline.
5. It accumulates the **entire session's audio** in `leftchannel` and creates playback recordings. Remove that functionality entirely. A continuous reading session must use bounded memory, not keep all audio.
6. Its default configuration has one inference thread, which is a useful starting point for a simple deployment. Moving inference into a dedicated Web Worker does not itself require WASM shared-memory multithreading.
7. It resets the keyword stream after detection. Preserve equivalent reset/re-arm semantics, plus application-level duplicate protection.

**Verdict:** promising and free, with no phrase training burden, but moderate engineering effort. Actual iPhone performance remains unknown. A no-API detector-only spike must come before enabling voice page turns.

## 7. Alternatives in more detail

### TensorFlow.js speech-commands: best small personal classifier fallback

The official module runs streaming recognition and transfer learning entirely in the browser. Its documented default vocabulary is digits plus `up/down/left/right/go/stop/yes/no`, noise, and unknown; the directional variant has `up/down/left/right`. **It does not natively recognize `next`, `back`, `sleep`, or `reader`.** [S13]

Three possible uses:

- **Fastest recognizer demonstration:** map `right → next`, `left → back`, `stop → pause listening`. No custom training, but different words and more accidental-trigger risk.
- **Personal calibration:** collect labeled examples for our words and background/other speech, then transfer-learn a small classifier in the browser. No paid training platform is needed.
- **Custom complete phrases:** train longer-window phrase classes. This is more work than replacing the list of labels; stock isolated-word windows may not contain a slowly spoken “reader next.”

The inspected default model's two weight shards total **5,874,736 bytes**, excluding TensorFlow.js itself. Code is Apache-2.0; preserve model and dataset notices when packaging instead of treating code licensing as sufficient for arbitrary third-party weights.

A few recordings can produce a demo, not evidence of robustness. Collect independent test recordings, natural negative speech, and variation in distance/volume/accent. A model trained on three positives plus silence can confidently misclassify ordinary conversation. Classifier scores are not calibrated guarantees.

The implementation uses an analyser and timer-based feature collection, not the proposed AudioWorklet/worker pipeline. Use it as a quick baseline or deliberately adapt its frontend; do not assume arbitrary audio sample rates or DSP features can replace its trained preprocessing unchanged.

**Why not first for exact phrases?** It exchanges WASM-build work for recording/training and ongoing false-trigger calibration. For a single user willing to train and possibly change command words, it could be simpler than sherpa; for configurable exact phrases without user training, sherpa is a better fit.

### Vosk-browser with a constrained grammar

Vosk-browser explicitly builds its WASM engine for a Web Worker. Its source supports passing a grammar to the recognizer. Vosk's official small US English model `vosk-model-small-en-us-0.15` is listed at **40 MB**, Apache-2.0. Suitable small models allow runtime vocabulary reconfiguration. [S14–S16]

Use complete allowed phrases plus unknown/rejection handling, rather than forcing all sound into three choices. All phrase words must exist in the model's vocabulary; a grammar is not new acoustic training.

It remains speech recognition internally, but entirely local: no remote transcript round trip. Final results usually involve endpointing, whereas partial results can change. Acting on every partial match risks duplicates and wrong turns; require exact/stable phrase logic and reset semantics.

**Why second choice?** Easier grammar configuration and an existing worker wrapper are useful, but its larger general speech model and transcript/endpoint handling are not as directly aligned with three instantaneous command events. Benchmark if sherpa's WASM packaging is impractical.

### openWakeWord and microWakeWord

openWakeWord is a credible wake-phrase project with frame-based local inference. However:

- Its official FAQ says a full browser JavaScript port is not provided; more than ONNX inference needs porting.
- Its `examples/web` path captures audio in the browser and sends it to a Python backend. That is **not** on-phone recognition.
- The code is Apache-2.0, but bundled pretrained models are **CC BY-NC-SA 4.0**, a different and more restrictive license. Custom phrase models need training and their own data/license review. [S17]

Community JS ports may reduce work, but need independent checks of DSP equivalence, model support, licenses, and target-Safari behavior. No examined community port establishes that evidence here.

microWakeWord is optimized for small streaming models on constrained devices. Its own README warns that training usable new models is difficult and the example notebook is not enough. Its DSP/runtime integration is not a ready-made PWA SDK. [S18]

**Verdict:** good candidates for later battery/performance optimization, not the least-complication initial build.

### Whisper and other local general STT

Whisper can run locally in WASM, and the project provides a streaming browser example. This is not inherently cloud-only. However, its general transcription task is far larger than our vocabulary. The unquantized tiny model cited by the browser example is 74 MB; quantization can reduce that, but does not remove decoding/windowing, CPU, and false-transcript handling work. [S19]

Batch real-time-factor benchmarks do not establish command response latency. VAD can reduce wasted work but adds another subsystem and can clip quiet speech. Transformers.js is a runtime route for such models, not by itself a small-vocabulary detector.

**Verdict:** useful for dictation, unnecessary as the first choice for three commands.

### Web Speech API: shortest demo, wrong reliability contract

`SpeechRecognition.continuous = true` requests continuous results; it does not guarantee indefinite microphone availability or fully local processing. Recognition can end or be interrupted. Restart loops do not repair all platform/permission/network conditions. [S20]

Current MDN browser compatibility data marks **`processLocally`, `available()`, and `install()` unsupported in Safari**, while prefixed recognition itself is supported. Therefore, we cannot rely on the standard API to force offline processing on the target iPhone. This does not prove every Safari recognition implementation always sends audio to a server; it means local execution is not a contract we can enforce with those APIs. [S21]

The old `SpeechGrammarList` approach is not a workaround: MDN says grammar features have been removed from active recognition behavior. Phrase biasing is also not a hard three-command grammar.

**Verdict:** acceptable throwaway demonstration only if browser-managed/cloud behavior is explicitly acceptable; not the recommendation here.

### Picovoice: technically relevant, excluded on cost terms

Porcupine supports web wake-word detection, and Rhino handles constrained speech-to-intent. Their web SDKs require a Picovoice AccessKey. The current vendor FAQ describes enterprise evaluation trials, monthly-active-user accounting for Porcupine/Rhino, no renewable trial, and no dedicated personal/non-commercial plans. [S22]

Do not repeat older claims of a permanent free personal tier without verifying current terms. On-device inference does not automatically mean free deployment or absence of license checks. These products do not meet this research's preferred no-paid-service/no-metered-dependency direction.

### Non-speech alternatives

- A clap/double-clap, whistle, or other sound-pattern detector can be local and simple, but cannot distinguish the spoken meanings of next/back/sleep. It trades vocabulary recognition for disruptive gestures and noise false triggers. Not recommended for reading in bed.
- A VAD only detects speech versus non-speech; it cannot tell which command was spoken.
- Template matching with MFCCs/dynamic time warping avoids a large pretrained model, but introduces speaker enrollment, endpointing, and sensitivity to speaking rate/noise. Not a clearly lower-effort reliable solution than existing KWS.
- A Bluetooth button or foot pedal can be reliable and avoid microphone/battery/privacy problems, but is not voice control and adds hardware cost. Treat it as a non-voice fallback, not fulfillment of this request.

## 8. Bare words versus a prefix: explicit decision

| Choice | Benefit | Cost/risk |
|---|---|---|
| `next`, `back`, `sleep` | Shortest speech and easiest mental model | Very common words; short acoustic evidence; TV/conversation can trigger genuine word matches |
| `reader next`, `reader back`, `reader sleep` as full phrases | More distinctive evidence; one detector; no separate wake/timeout stage | Takes longer to say; quiet/poorly articulated prefix can increase misses |
| `reader` → armed interval → `next/back/sleep` | Familiar voice-assistant pattern; potentially useful with many commands | Two-stage state, command window and buffer handling, possible additional model/training; harder than necessary here |

**Choose full prefixed phrases for our own recognizer.** This optimizes for fewer surprising actions and avoids the engineering effort of a separate wake-word system. It is not inherently faster than bare commands, and “reader” is a starting phrase rather than an acoustically optimized wake word.

Use `Tap Next/Back` for the OS Voice Control trial because those are already supported named-control commands and require the least setup. The preferred spoken syntax can differ between the zero-code alternative and the custom embedded engine.

A prefix is not authentication or speaker verification. If a TV or another person says the exact phrase, the detector can legitimately recognize it. Do not enable destructive actions based solely on voice, and do not claim voice commands prove the owner's identity.

## 9. Proposed PWA audio architecture

```text
Explicit Start tap
    ├─ acquire foreground wake lock
    ├─ load/warm pinned local model assets
    └─ request microphone permission / resume AudioContext
                   │
       getUserMedia microphone stream
                   │
       AudioWorklet: bounded PCM framing
                   │
       Worker: streaming resampler + local KWS
                   │
       command event + session generation + timestamp
                   │
       active-session / freshness / duplicate / pending guards
                   │
       explicit allowlist: NEXT → POST /next, BACK → POST /back
                   │
       existing bearer token + HTTPS + exact-origin CORS
```

### Capture and execution

- Request mono audio as a preference; inspect the actual capture/audio-context sample rate. A requested 16 kHz rate is not proof the device supplies it. Use a streaming resampler matched to model requirements; do not merely relabel 44.1/48 kHz audio as 16 kHz.
- Use AudioWorklet for lightweight audio framing. Perform heavy decoding in a dedicated Web Worker, not in the worklet's real-time audio callback or on the UI thread. [S5]
- Use transferable buffers with a small bounded queue. The main thread may relay messages if necessary; avoid depending on `SharedArrayBuffer` for the first build.
- Bound both queued audio and command age. If processing falls behind or the session is interrupted, discard stale frames, reset decoder state, and show recovery rather than executing commands from old audio.
- Consider echo cancellation/noise suppression through an A/B test. Device/browser implementations vary; automatic gain control can amplify distant conversation. A VAD is optional optimization, not a required first dependency.
- Do not loop microphone audio to the speaker. If an output connection is required to keep the processing graph active, ensure output is silent—not feedback or an OS keep-alive trick.
- Stop capture tracks and release audio/model resources on explicit Stop. For interruptions, show a truthful unavailable state and require a tap to resume if the browser requires it.

### Model loading and hosting

- Ship version-pinned JS/WASM/model files as static assets. No inference server is required.
- Verify expected file hashes/sizes at packaging, keep licenses, and warm the model before showing **Listening**.
- Cache public immutable assets deliberately. The current service worker pre-caches only the small shell and does not automatically cache arbitrary fetched model files; model/offline-readiness work would be needed.
- Avoid a deployment that requires cross-origin-isolated WASM multithreading initially. ONNX Runtime documents that multithreading requires `crossOriginIsolated`; single-thread inference in a Worker avoids that requirement. GitHub Pages does not provide a normal arbitrary-header configuration mechanism, so COOP/COEP-dependent builds introduce hosting/workaround complexity. [S23–S24]
- `onnxruntime-web` configuration applies only if that runtime is used directly; sherpa's Emscripten build has its own build/runtime configuration. Setting `ort.env.wasm.numThreads` in unrelated JS does not reconfigure sherpa's compiled runtime.
- WASM SIMD and model operator support must be verified on the actual Safari build. Do not depend on WebGPU just because a desktop demo uses it.
- The model can work offline after assets are available; Kindle network delivery remains a separate dependency.

### Dispatch and safety

- Map a detector ID to an explicit action allowlist. Never construct arbitrary API paths from unrestricted recognized text.
- Route voice and touch through the same command controller.
- Reset/re-arm after one recognized phrase; tune a brief refractory interval/return-to-background requirement against natural repetition. Cooldown alone is not proof of one utterance → one action.
- Keep at most one HTTP command in flight. Do not queue extra voice detections for later turns.
- For ambiguous HTTP timeout/network failure, pause automatic voice dispatch and ask the user to inspect/re-arm. Otherwise repeated recognition could effectively retry an already accepted turn.
- The current sender already avoids automatic retries and rejects concurrent sends, but it does **not** yet have voice utterance deduplication, stale-audio handling, or an explicit uncertain-result re-arm state. Those would be new work.
- Keep bearer tokens out of audio workers, logs, model assets, and URLs. Recognition only needs to send a small command event to the main controller.
- A private tailnet and token protect the network boundary, not the acoustic input. Keep them even with local voice detection.

## 10. `sleep` must not be guessed

The existing plugin exposes only authenticated `POST /next` and `POST /back`. It has no `/sleep` route. Existing product guardrails preserve normal Kindle sleep and forbid unapproved power-setting changes.

Possible meanings are not equivalent:

| Meaning | Consequence |
|---|---|
| End the PWA listening session | Stop microphone and release wake lock; restarting needs a tap if no listener remains |
| Pause actions but keep a wake-word listener | Can support voice reactivation later, but microphone is still active and needs an honest indicator |
| Suspend the Kindle | Requires a separately designed/approved API and lifecycle checks; may disconnect Tailscale and cannot imply remote wake |
| OS Voice Control “Go to sleep” | Pauses OS command listening behavior; not a Kindle API action |

**Research recommendation:** keep “reader sleep” detection-only in the prototype. The least-risk eventual meaning is “end this phone listening session,” but this is proposed, not confirmed. Never substitute an OS sleep command or add remote Kindle suspend silently.

## 11. Validation plan: evidence before API actions

### Stage A — zero-code alternative

Try iOS Voice Control with named PWA buttons. Record setup friction, exact phrases, action delay, reading posture, interruption behavior, and false activations. If it satisfies the personal-use goal, no custom speech engine may be necessary.

### Stage B — detector-only embedded spike

If PWA-owned recognition remains desired:

1. Build the English sherpa KWS path with complete phrases, bounded audio memory, worker execution, and a measured heap configuration.
2. Run on the actual iPhone in both Safari and Home Screen mode. Display detections and timings only; send **no Kindle commands**.
3. Record first-load bytes/time separately from warm recognition latency. Verify startup on a non-cross-origin-isolated deployment representative of Pages.
4. Inspect network traffic: no raw audio/transcripts or license calls should leave the phone. After assets are loaded, test recognition with networking unavailable; this tests the recognizer, not Kindle control.
5. If build/heap/latency/thermal cost is unacceptable, compare Vosk grammar or TF.js personal classification instead of forcing the first engine through.

### Proposed measurements and provisional targets

These are experiment targets, not observed results or a roadmap phase-exit revision:

- **Command test:** at least 50 utterances per configured phrase across normal/quiet speech, realistic phone-to-mouth distance, and reading posture. Keep test utterances separate from any training/tuning recordings. Initial target: ≥95% detected, zero wrong-direction actions, zero duplicate events from a single utterance.
- **Latency:** acoustic phrase-end → detection p50/p95, then detection → dispatch and API RTT separately. Initial p95 detection target ≤500 ms after phrase end. Calibrated test clips or explicitly consented evaluation recordings are needed for accurate phrase-end timing; ordinary application logs alone cannot infer it exactly.
- **Negative audio:** at least two hours of representative silence, conversation, podcast/TV speech, and confusable terms without intended commands. Initial target: zero unintended action candidates. Deliberately include the bare words and near-matches, not only quiet-room noise.
- **Statistical honesty:** zero false triggers in two hours is only a screening result. Under a simple Poisson assumption, zero events over T hours gives an approximate 95% upper rate bound of 3/T per hour. Two clean hours do not establish “less than one false turn every ten hours”; roughly 30 clean representative hours would be needed for that bound, and real environments may differ.
- **Resource/session test:** two 30-minute foreground sessions with bounded memory, no growing audio buffer, no thermal warning or unexpected suspension. Compare battery drop/temperature with the same PWA/wake lock and no microphone inference. No battery claim without actual measurements.
- **Interruption test:** app switch, manual lock, incoming call, microphone permission change, audio-route change, and wake-lock release. UI must not falsely show active listening; no old command may fire on return.
- **Duplicate/repeat test:** one phrase, deliberately repeated phrases, long pauses between prefix and command, fast repeats, and a held/elongated final syllable. Verify one accepted utterance does not become multiple turns.

### Stage C — controlled API integration

Only after the detector-only test:

- Connect voice events to the existing authenticated sender.
- Test one Next and one Back with visible Kindle verification before longer sessions.
- Test wrong token, Kindle menu open, network timeout, Tailscale disconnected, Kindle normal sleep, and recovery with no replay.
- Keep touch controls and explicit Stop available.
- Leave `sleep` unbound until its meaning and consequences are approved.

Transport and wake-lock feasibility remain independent gates. Local speech inference does not solve the earlier HTTPS-to-HTTP browser problem or establish private Serve connectivity.

## 12. Bottom line

**For the owner's “least complications, no paid service” preference: first test Apple Voice Control with “Tap Next/Back.”** It can reuse the current PWA without building a recognizer.

**For the exact “recognizer inside my PWA” requirement: investigate sherpa-onnx local phrase spotting with “reader next/back,” not cloud STT and not a separate wake-word stage.** It avoids per-user training and fees, but must pass an iPhone-specific engineering spike. TF.js personal classification and Vosk grammar are meaningful free fallback options, not paid services in disguise.

No source research can honestly promise uninterrupted locked-screen PWA listening, zero false triggers, or a measured response time on a phone we have not tested.

## Sources and audit trail

Primary docs/source were retrieved on 2026-09-21. Vendor capability claims and upstream examples are not target-device benchmarks. Some documentation reflects moving main branches; source revisions used for detailed code observations are pinned below.

- **S1 — Apple Voice Control:** https://support.apple.com/en-us/111778 — setup, offline use after download, named taps, sleep/wake and Attention Aware.
- **S2 — Apple Voice Control guide:** https://support.apple.com/guide/iphone/use-voice-control-iph2c21a3c88/ios — offline languages, Command mode and listening lifecycle.
- **S3 — Apple custom commands:** https://support.apple.com/kb/HT210418 — command customization, recorded actions, app scoping and confirmation settings.
- **S4 — getUserMedia:** https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia — secure context, permissions and device constraints.
- **S5 — AudioWorklet:** https://developer.mozilla.org/en-US/docs/Web/API/AudioWorklet — separate audio-processing thread and secure-context requirement.
- **S6 — iOS audio interruption:** https://developer.mozilla.org/en-US/docs/Web/API/BaseAudioContext/state — interrupted contexts when leaving Safari/turning off screen.
- **S7 — Screen Wake Lock:** https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API ; https://webkit.org/blog/16574/webkit-features-in-safari-18-4/ — lifecycle limits and Home Screen web-app support.
- **S8 — sherpa keyword spotting:** https://k2-fsa.github.io/sherpa/onnx/kws/index.html — constrained decoder, arbitrary configured keywords, thresholds and tokenization.
- **S9 — sherpa pretrained model details:** https://k2-fsa.github.io/sherpa/onnx/kws/pretrained_models/index.html#sherpa-onnx-kws-zipformer-gigaspeech-3-3m-2024-01-01-english ; https://github.com/k2-fsa/sherpa-onnx/releases/tag/kws-models — model files, sizes and examples.
- **S10 — model-specific license metadata:** https://modelscope.cn/api/v1/models/pkufool/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01 — `License: Apache License 2.0`; model publisher `pkufool`, revision `master`. This is the metadata actually retrieved; attempted Hugging Face mirrors were unavailable and are not relied on.
- **S11 — sherpa WASM KWS source:** https://github.com/k2-fsa/sherpa-onnx/tree/1d04ac4d666430e911f526d9ae55a26a859159cd/wasm/kws — inspected `CMakeLists.txt`, `app.js`, `sherpa-onnx-kws.js`, `assets/README.md`; 512 MB initial heap, ScriptProcessor audio and session recording are visible in source.
- **S12 — sherpa build and license:** https://github.com/k2-fsa/sherpa-onnx/blob/1d04ac4d666430e911f526d9ae55a26a859159cd/build-wasm-simd-kws.sh ; https://github.com/k2-fsa/sherpa-onnx/blob/1d04ac4d666430e911f526d9ae55a26a859159cd/LICENSE .
- **S13 — TensorFlow.js speech-commands:** https://github.com/tensorflow/tfjs-models/tree/c731b9ebbd6f4c9e8bf99b0df76bbdbf9c25b07f/speech-commands — README and `src/browser_fft_extractor.ts`; https://storage.googleapis.com/tfjs-models/tfjs/speech-commands/v0.4/browser_fft/18w/model.json — actual manifest; shard HTTP headers showed 4,194,304 and 1,680,432 bytes.
- **S14 — Vosk-browser:** https://github.com/ccoreilly/vosk-browser/tree/4b8eb257503108d96819854d3984372903c2259e — README, `lib/src/model.ts`, `lib/src/worker.ts`, Apache-2.0 COPYING; worker build and grammar arguments confirmed in source.
- **S15 — Vosk model catalog:** https://alphacephei.com/vosk/models — US English small model size and model-specific license.
- **S16 — Vosk vocabulary adaptation:** https://alphacephei.com/vosk/adaptation — dynamic vocabulary and model restrictions.
- **S17 — openWakeWord:** https://github.com/dscripka/openWakeWord/blob/368c03716d1e92591906a84949bc477f3a834455/README.md — architecture, 80 ms frames, browser-port caveat, Python-backed web examples, separate model license.
- **S18 — microWakeWord:** https://github.com/OHF-Voice/micro-wake-word/blob/4665173cd35f1cff9a61e06fc427f124766c488e/README.md — streaming architecture and explicit custom-training difficulty warning.
- **S19 — Whisper browser examples:** https://github.com/ggml-org/whisper.cpp/tree/master/examples/whisper.wasm ; https://github.com/ggml-org/whisper.cpp/tree/master/examples/stream.wasm — local/browser feasibility, model size, source example limitations; not iPhone timing evidence.
- **S20 — Web Speech API:** https://developer.mozilla.org/en-US/docs/Web/API/SpeechRecognition ; https://developer.mozilla.org/en-US/docs/Web/API/Web_Speech_API/Using_the_Web_Speech_API — server-dependent behavior, local APIs, continuous-result semantics and obsolete grammars.
- **S21 — browser compatibility source:** https://github.com/mdn/browser-compat-data/blob/main/api/SpeechRecognition.json — retrieved Safari `processLocally`, `available_static`, `install_static` and `phrases` entries have `version_added: false`; iOS entries mirror Safari.
- **S22 — Picovoice:** https://picovoice.ai/docs/quick-start/porcupine-web/ ; https://picovoice.ai/docs/quick-start/rhino-web/ ; https://picovoice.ai/docs/faq/general/ — AccessKey, enterprise trial/usage accounting and current personal-use answer. The pricing page did not yield usable text, so no exact price is asserted.
- **S23 — ONNX Runtime browser deployment:** https://onnxruntime.ai/docs/tutorials/web/ ; https://onnxruntime.ai/docs/tutorials/web/env-flags-and-session-options.html — local inference, Worker proxy and cross-origin-isolation requirement for multithreading.
- **S24 — Pages header limitation discussion (support/community evidence, not a browser standard):** https://github.com/orgs/community/discussions/13309 — lack of arbitrary COOP/COEP configuration; verify actual deployment headers before selecting a threaded build.

### Existing project evidence

- `mobile-pwa/app.js`: one-shot authenticated fetch, pending-request guard, three-second timeout, wake-lock UI; no microphone recognizer or voice deduplication yet.
- `mobile-pwa/service-worker.js`: shell-only precache, no command interception/replay; models are not currently cached automatically.
- `pageturner.koplugin/pageturner_http.lua`: next/back-only bodyless API and exact Pages-origin CORS; no sleep endpoint.
- The target iPhone hardware/exact OS build and combined installed-PWA transport/wake behavior remain unverified. The Kindle Tailscale launch and 15-second daemon tests say nothing about phone audio inference performance.
