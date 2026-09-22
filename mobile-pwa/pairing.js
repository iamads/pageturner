import { parseEndpoint } from "./endpoint.js";

const TOKEN_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;

export function parseConnection(endpoint, token) {
  if (typeof token !== "string" || !TOKEN_PATTERN.test(token)) {
    throw new Error("Enter the 32–128 character Page Turner token.");
  }
  return {...parseEndpoint(endpoint), token};
}

// Only URL data is handled here, never camera frames or QR decoding.
export function parsePairingFragment(raw) {
  const invalid = () => new Error("Invalid pairing link. Scan the current Kindle code or enter the connection manually.");
  if (typeof raw !== "string" || !raw.startsWith("#") || raw.length > 4096) throw invalid();
  // URLSearchParams tolerates malformed percent escapes; reject them explicitly.
  try { decodeURIComponent(raw.slice(1)); } catch { throw invalid(); }
  const params = new URLSearchParams(raw.slice(1));
  if ([...params.keys()].sort().join(",") !== "endpoint,token,version"
      || params.get("version") !== "1") throw invalid();
  try {
    return parseConnection(params.get("endpoint"), params.get("token"));
  } catch {
    throw invalid();
  }
}

export function consumePairingFragment(location, history) {
  const fragment = location.hash;
  if (!fragment) return null;
  // Clear even invalid data before validation/fetch/diagnostics. No credentials
  // in history state, storage, requests to the frontend host, or error messages.
  history.replaceState(null, "", location.pathname + location.search);
  return parsePairingFragment(fragment);
}
