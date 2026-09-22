import assert from "node:assert/strict";
import test from "node:test";

import { parseEndpoint } from "../mobile-pwa/endpoint.js";
import { parseConnection, parsePairingFragment, consumePairingFragment } from "../mobile-pwa/pairing.js";

const tailnetHost = "pageturner-kindle.example-tailnet.ts.net";

test("bare IPv4 uses direct HTTP and the Page Turner default port", () => {
  assert.deepEqual(parseEndpoint("192.168.1.42"), {
    baseUrl: "http://192.168.1.42:8088",
    protocol: "http",
    host: "192.168.1.42",
    port: 8088,
    transport: "direct",
  });
});

test("IPv4 accepts an inline port or complete HTTP URL", () => {
  assert.equal(parseEndpoint("192.168.1.42:8089").baseUrl, "http://192.168.1.42:8089");
  assert.equal(parseEndpoint("http://192.168.1.42:8089/").baseUrl, "http://192.168.1.42:8089");
});

test("bare Tailscale hostname uses HTTPS port 443", () => {
  assert.deepEqual(parseEndpoint(tailnetHost), {
    baseUrl: `https://${tailnetHost}`,
    protocol: "https",
    host: tailnetHost,
    port: 443,
    transport: "tailscale",
  });
});

test("Tailscale hostname accepts an inline port or complete HTTPS URL", () => {
  assert.equal(parseEndpoint(`${tailnetHost}:443`).baseUrl, `https://${tailnetHost}`);
  assert.equal(parseEndpoint(`https://${tailnetHost}:8443/`).baseUrl, `https://${tailnetHost}:8443`);
});

test("normalizes hostname case", () => {
  assert.equal(
    parseEndpoint("HTTPS://PAGETURNER-KINDLE.EXAMPLE-TAILNET.TS.NET").baseUrl,
    `https://${tailnetHost}`,
  );
});

const token = "a".repeat(64);
const fragment = (endpoint = tailnetHost) => `#version=1&endpoint=${encodeURIComponent(endpoint)}&token=${token}`;

test("pairing fragment parses direct and Tailscale endpoints using manual validation", () => {
  for (const endpoint of ["http://192.168.1.42:8088", `https://${tailnetHost}:8443`]) {
    assert.deepEqual(parsePairingFragment(fragment(endpoint)), parseConnection(endpoint, token));
  }
});

test("pairing fragment rejects malformed, duplicate, unsupported and unsafe data", () => {
  for (const payload of [
    "not a fragment", "#", null, "#" + "x".repeat(4096),
    JSON.stringify({version: 1, endpoint: tailnetHost, token}),
    fragment().replace("version=1", "version=2"),
    fragment("https://evil.example"),
    fragment(`https://${tailnetHost}/next`),
    fragment().replace(token, "short"),
    fragment().replace(`&token=${token}`, ""),
    fragment() + "&extra=true",
    fragment() + "&version=1",
    fragment() + `&token=${token}`,
    fragment() + `&endpoint=${tailnetHost}`,
    fragment() + `&%74oken=${token}`,
    fragment().replace(token, "%ZZ"),
    fragment().replace(token, "%E0%A4"),
  ]) {
    assert.throws(() => parsePairingFragment(payload), (error) => {
      assert(!error.message.includes(token));
      return /Invalid pairing link/.test(error.message);
    });
  }
});

test("consumes and clears even invalid fragments before parsing; plain visit is untouched", () => {
  for (const hash of [fragment(), "#invalid"]) {
    const location = {hash, pathname: "/pageturner/", search: ""};
    const calls = [];
    const history = {replaceState: (...args) => calls.push(args)};
    try { consumePairingFragment(location, history); } catch { /* expected invalid */ }
    assert.deepEqual(calls, [[null, "", "/pageturner/"]]);
  }
  assert.equal(consumePairingFragment({hash: ""}, {
    replaceState() { assert.fail("plain visit should not rewrite history"); },
  }), null);
});

for (const [name, endpoint] of [
  ["blank input", ""],
  ["invalid IPv4", "192.168.1.999"],
  ["IPv4 with leading zeros", "192.168.001.42"],
  ["arbitrary hostname", "kindle.example.com"],
  ["incomplete Tailscale hostname", "ts.net"],
  ["HTTPS direct IP", "https://192.168.1.42"],
  ["HTTP Tailscale hostname", `http://${tailnetHost}`],
  ["command path", `https://${tailnetHost}/next`],
  ["query string", `https://${tailnetHost}?token=nope`],
  ["fragment", `https://${tailnetHost}#next`],
  ["credentials", `https://user@${tailnetHost}`],
  ["zero port", "192.168.1.42:0"],
  ["out-of-range port", `${tailnetHost}:65536`],
]) {
  test(`rejects ${name}`, () => {
    assert.throws(() => parseEndpoint(endpoint), Error);
  });
}
