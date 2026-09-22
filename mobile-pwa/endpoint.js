const IPV4_PART = /^(?:0|[1-9][0-9]{0,2})$/;
const DNS_LABEL = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

function isIPv4(host) {
  const parts = host.split(".");
  return parts.length === 4
    && parts.every((part) => IPV4_PART.test(part) && Number(part) <= 255);
}

function isTailscaleHostname(host) {
  const labels = host.split(".");
  return labels.length >= 3
    && labels.slice(-2).join(".") === "ts.net"
    && labels.every((label) => DNS_LABEL.test(label));
}

export function parseEndpoint(raw) {
  const value = raw.trim();
  const match = value.match(/^(?:(https?):\/\/)?([^/?#:@]+)(?::([0-9]+))?\/?$/i);
  if (!match) {
    throw new Error("Enter a Kindle IPv4 address or Tailscale HTTPS URL without a path.");
  }

  const suppliedProtocol = match[1] ? match[1].toLowerCase() : null;
  const host = match[2].toLowerCase();
  const suppliedPort = match[3];
  const ipv4 = isIPv4(host);
  const tailscale = isTailscaleHostname(host);

  if (!ipv4 && !tailscale) {
    throw new Error("Enter a valid Kindle IPv4 address or *.ts.net hostname.");
  }

  const protocol = suppliedProtocol || (tailscale ? "https" : "http");
  if (ipv4 && protocol !== "http") {
    throw new Error("A direct Kindle IP connection must use HTTP.");
  }
  if (tailscale && protocol !== "https") {
    throw new Error("A Tailscale hostname must use HTTPS.");
  }

  const port = suppliedPort === undefined
    ? (tailscale ? 443 : 8088)
    : Number(suppliedPort);
  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("Port must be between 1 and 65535.");
  }

  const standardPort = protocol === "https" ? 443 : 80;
  const authority = port === standardPort ? host : `${host}:${port}`;
  return {
    baseUrl: `${protocol}://${authority}`,
    protocol,
    host,
    port,
    transport: tailscale ? "tailscale" : "direct",
  };
}
