import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import {readFileSync, statSync, openSync, readSync, closeSync} from "node:fs";
import {VoiceSession, validDetection} from "../mobile-pwa/voice-session.js";
import {ACTIVE_DETECTOR} from "../mobile-pwa/detector-config.js";
import {createDetector as createVoskDetector, exactCommand} from "../mobile-pwa/vosk-detector.js";

const workerCode = readFileSync(new URL("../mobile-pwa/voice-detector-worker.js", import.meta.url), "utf8");
const workletCode = readFileSync(new URL("../mobile-pwa/voice-capture-worklet.js", import.meta.url), "utf8");
const vendor = new URL("../mobile-pwa/vendor/sherpa-onnx/", import.meta.url);
const voskVendor = new URL("../mobile-pwa/vendor/vosk/", import.meta.url);

test("code-level detector selection accepts either packaged detector", () => {
  assert(["sherpa", "vosk"].includes(ACTIVE_DETECTOR));
});

test("Vosk runtime and locally hosted English model are packaged", () => {
  assert(statSync(new URL("vosk.js", voskVendor)).size > 5_000_000);
  const model = new URL("model.tar.gz", voskVendor);
  assert(statSync(model).size > 35_000_000);
  const fd = openSync(model, "r");
  try {
    const magic = Buffer.alloc(2);
    readSync(fd, magic, 0, 2, 0);
    assert.equal(magic.toString("hex"), "1f8b");
  } finally { closeSync(fd); }
});

test("Vosk accepts only final exact bare words and passes local PCM without command effects", async () => {
  for (const [text, command] of [[" Next ", "next"], ["back", "back"], ["sleep", "sleep"],
    ["back next", null], ["backward", null], ["[unk]", null], ["", null], [null, null]]) {
    assert.equal(exactCommand(text), command);
  }
  const previous = Object.fromEntries(["self", "importScripts"].map((key) => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
  const listeners = new Map();
  let grammar, seenAudio, deleted = false;
  const model = {
    on(event, cb) { listeners.set(`model:${event}`, cb); },
    KaldiRecognizer: class {
      constructor(rate, list) { assert.equal(rate, 16000); grammar = JSON.parse(list); }
      on(event, cb) { listeners.set(event, cb); }
      acceptWaveformFloat(samples, rate) { seenAudio = samples; assert.equal(rate, 16000); }
      remove() { deleted = true; }
    },
    terminate() {},
  };
  const recognized = [];
  try {
    globalThis.self = {location: {href: "http://localhost:4173/voice-detector-worker.js"},
      Vosk: {createModel: async (url) => {
        assert.match(url, /^http:\/\/localhost:4173\/vendor\/vosk\/model.tar.gz$/);
        return model;
      }}};
    globalThis.importScripts = (path) => assert.equal(path, "./vendor/vosk/vosk.js");
    const detector = await createVoskDetector((word) => recognized.push(word));
    const pcm = new Float32Array([0.25, -0.25]);
    detector.accept(pcm, 16000);
    assert.equal(seenAudio, pcm);
    assert.deepEqual(grammar, ["next", "back", "sleep", "[unk]"]);
    listeners.get("result")({result: {text: "back next"}});
    listeners.get("result")({result: {text: "next"}});
    listeners.get("partialresult")?.({result: {partial: "back"}});
    assert.deepEqual(recognized, ["next"]);
    detector.dispose();
    assert.equal(deleted, true);
  } finally {
    for (const [key, descriptor] of Object.entries(previous)) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor);
      else delete globalThis[key];
    }
  }
});

test("self-hosted English KWS runtime, model and three bare keywords are packaged", () => {
  const words = readFileSync(new URL("keywords.txt", vendor), "utf8").trim().split("\n");
  assert.deepEqual(words, ["▁NEXT @next", "▁BACK @back", "▁S LE E P @sleep"]);
  const js = readFileSync(new URL("sherpa-onnx-wasm-kws-main.js", vendor), "utf8");
  for (const filename of ["encoder.onnx", "decoder.onnx", "joiner.onnx", "tokens.txt", "bpe.model"]) {
    assert(js.includes(filename), `preloaded model is missing ${filename}`);
  }
  assert(statSync(new URL("sherpa-onnx-wasm-kws-main.data", vendor)).size > 4_000_000);
  const wasm = new URL("sherpa-onnx-wasm-kws-main.wasm", vendor);
  assert(statSync(wasm).size > 8_000_000);
  const fd = openSync(wasm, "r");
  try {
    const magic = Buffer.alloc(4);
    readSync(fd, magic, 0, 4, 0);
    assert.equal(magic.toString("hex"), "0061736d");
  } finally { closeSync(fd); }
});

test("capture forwards bounded PCM to the Worker and releases everything on Stop", async () => {
  const previous = Object.fromEntries(["window", "navigator", "AudioContext", "AudioWorkletNode", "Worker"].map((key) => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
  const tracks = [{stopped: false, stop() { this.stopped = true; }, addEventListener() {}}];
  let worker;
  let audioNode;
  let context;
  try {
    Object.defineProperty(globalThis, "navigator", {configurable: true, value: {mediaDevices: {getUserMedia: async () => ({getTracks: () => tracks, getAudioTracks: () => tracks})}}});
    globalThis.window = {AudioWorkletNode: class {}};
    globalThis.AudioContext = class {
      constructor() {
        context = this;
        this.sampleRate = 48000;
        this.state = "running";
        this.audioWorklet = {addModule: async (name) => assert.equal(name, "voice-capture-worklet.js")};
        this.destination = {};
      }
      createMediaStreamSource() { return {connect() {}, disconnect() {}}; }
      createGain() { return {gain: {value: 1}, connect() {}, disconnect() {}}; }
      async resume() {}
      async close() { this.state = "closed"; }
    };
    globalThis.AudioWorkletNode = class {
      constructor() { audioNode = this; this.port = {onmessage: null}; }
      connect() {}
      disconnect() {}
    };
    globalThis.Worker = class {
      constructor() { worker = this; this.messages = []; }
      postMessage(message) {
        this.messages.push(message);
        if (message.type === "init") queueMicrotask(() => this.onmessage({data: {type: "ready", sessionId: message.sessionId}}));
      }
      terminate() { this.terminated = true; }
    };
    const received = [];
    const session = new VoiceSession({onCommand: (word) => received.push(word), onState: () => {}});
    assert.equal(await session.start("test"), true);
    const id = worker.messages[0].sessionId;
    for (let i = 0; i < 25; i++) audioNode.port.onmessage({data: new Float32Array(1024)});
    assert.equal(worker.messages.filter((m) => m.type === "audio").length, 19);
    worker.onmessage({data: {type: "ack", sessionId: id}});
    audioNode.port.onmessage({data: new Float32Array(1024)});
    assert.equal(worker.messages.filter((m) => m.type === "audio").length, 20);
    worker.onmessage({data: {type: "detection", sessionId: id, command: "next"}});
    await session.stop();
    worker.onmessage({data: {type: "detection", sessionId: id, command: "back"}});
    assert.deepEqual(received, ["next"]);
    assert(tracks[0].stopped && worker.terminated);
    assert.equal(context.state, "closed");
  } finally {
    for (const [key, descriptor] of Object.entries(previous)) {
      if (descriptor) Object.defineProperty(globalThis, key, descriptor);
      else delete globalThis[key];
    }
  }
});

test("only known, current-session command events are accepted", () => {
  assert(validDetection({type: "detection", sessionId: 2, command: "sleep"}, 2));
  for (const event of [
    {type: "detection", sessionId: 1, command: "next"},
    {type: "detection", sessionId: 2, command: "delete"},
    {type: "ack", sessionId: 2, command: "back"},
  ]) assert.equal(validDetection(event, 2), false);
});

function runWorker(hostname) {
  const sent = [];
  const self = {location: {hostname}, postMessage(message) { sent.push(message); }};
  const context = vm.createContext({self, Float32Array, Number, Set, Error, performance});
  vm.runInContext(workerCode, context);
  return {
    sent,
    async post(data) { await self.onmessage({data}); },
  };
}

test("simulated detector only runs on localhost and never emits automatically from PCM", async () => {
  const local = runWorker("localhost");
  await local.post({type: "init", sessionId: 7, mode: "test"});
  assert.equal(local.sent[0].type, "ready");
  await local.post({type: "audio", sessionId: 7, sampleRate: 48000, samples: new Float32Array(1024)});
  assert.equal(local.sent[1].type, "ack");
  await local.post({type: "simulate", sessionId: 7, command: "next"});
  assert.equal(local.sent[2].command, "next");
  await local.post({type: "simulate", sessionId: 6, command: "back"});
  await local.post({type: "simulate", sessionId: 7, command: "unknown"});
  assert.equal(local.sent.length, 3);

  const remote = runWorker("iamads.github.io");
  await remote.post({type: "init", sessionId: 1, mode: "test"});
  assert.equal(remote.sent[0].type, "error");
  await remote.post({type: "simulate", sessionId: 1, command: "next"});
  assert.equal(remote.sent.length, 1);
});

test("audio worklet sends bounded mono chunks and silent output without retaining a session recording", () => {
  let Capture;
  const context = vm.createContext({
    Float32Array,
    AudioWorkletProcessor: class { constructor() { this.port = {postMessage: (data) => messages.push(data)}; } },
    registerProcessor: (_name, value) => { Capture = value; },
  });
  const messages = [];
  vm.runInContext(workletCode, context);
  const node = new Capture();
  const a = new Float32Array(128).fill(0.8);
  const b = new Float32Array(128).fill(0.2);
  for (let i = 0; i < 8; i++) {
    const output = new Float32Array(128).fill(1);
    assert.equal(node.process([[a, b]], [[output]]), true);
    assert(output.every((x) => x === 0));
  }
  assert.equal(messages.length, 1);
  assert.equal(messages[0].length, 1024);
  assert(Math.abs(messages[0][0] - 0.5) < 1e-6);
  assert.equal(node.used, 0);
  assert.equal(node.chunk.length, 1024);
});
