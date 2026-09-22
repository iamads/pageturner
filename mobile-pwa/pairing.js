import { parseEndpoint } from "./endpoint.js";

const TOKEN_PATTERN = /^[A-Za-z0-9_-]{32,128}$/;

export function parsePairingPayload(raw) {
  if (typeof raw !== "string" || raw.length === 0 || raw.length > 4096) {
    throw new Error("This is not a valid Page Turner pairing code.");
  }

  let value;
  try {
    value = JSON.parse(raw);
  } catch {
    throw new Error("This QR code does not contain valid Page Turner pairing data.");
  }

  const keys = value && typeof value === "object" && !Array.isArray(value)
    ? Object.keys(value).sort().join(",")
    : "";
  if (keys !== "endpoint,token,version" || value.version !== 1
      || typeof value.endpoint !== "string" || typeof value.token !== "string") {
    throw new Error("This QR code uses unsupported pairing data.");
  }
  if (!TOKEN_PATTERN.test(value.token)) {
    throw new Error("This QR code contains an invalid pairing token.");
  }

  const endpoint = parseEndpoint(value.endpoint);
  return {...endpoint, token: value.token};
}
