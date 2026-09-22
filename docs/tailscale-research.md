# Tailscale research for the mobile PWA

> Status: Research only; nothing installed, configured, or exposed
> Researched: 2026-09-19
> Goal: Keep the HTTPS PWA and foreground wake lock, tolerate changing Kindle Wi-Fi IPs, and avoid manually provisioning Kindle certificates.

## Findings at a glance

Tailscale is a plausible alternative to building our own relay. Community Kindle integrations already exist. However, **Tailscale alone is a private network, not a public HTTPS endpoint**. Two additional features matter:

| Mode | Endpoint | Phone needs Tailscale? | HTTPS handling | Main trade-off |
|---|---|---|---|---|
| Ordinary tailnet HTTP | Private Tailscale IP/name | Yes | None at browser URL level | Does not itself solve HTTPS-page → HTTP restrictions |
| Tailscale Serve | Private `https://device.tailnet.ts.net` | Yes, connected | Tailscale provisions/manages TLS | Phone VPN setup; private-network browser permissions still need testing |
| Tailscale Funnel | Public `https://device.tailnet.ts.net` | No | Tailscale provisions/manages TLS; public relay forwards encrypted traffic | Public exposure and relay dependency; security hardening required |

Both Serve and Funnel use a node hostname, not the Kindle's changing Wi-Fi IP. The certificate does not need replacing for each Wi-Fi IP change. Node registration/state and chosen hostname must persist; removing/re-registering or renaming the node can affect the endpoint.

These options **still use HTTPS**, but remove the manual IP-certificate/local-DNS work previously rejected. Tailscale handles the hostname and certificate rather than the KOReader plugin implementing TLS.

## Option A: Tailscale Serve — private

```text
GitHub Pages PWA on iPhone
    → https://kindle.<tailnet>.ts.net
    → iPhone Tailscale connection → Kindle tailscaled/Serve
    → http://127.0.0.1:8088 → Page Turner
```

- Install Tailscale on the Kindle and iPhone and authorize them in the same tailnet (or configure suitable sharing/access rules).
- Serve terminates HTTPS on the Kindle and proxies to the existing plain-HTTP Page Turner listener.
- Browser sees a valid HTTPS API; GitHub Pages remains the secure frontend supporting wake lock.
- Existing narrowly scoped Pages-origin CORS and bearer-token authentication remain useful and required.
- Tailscale access rules add a private-network access boundary; they do not replace our application token.
- No publicly reachable Page Turner endpoint is necessary.
- Tailscale may establish a direct connection or use its encrypted relay infrastructure. Direct peer-to-peer delivery and latency are not guaranteed.

Trade-offs: iPhone VPN configuration/connection, account and node-key lifecycle, possible coexistence issues with another VPN, and remaining browser local-network permission checks. Serve solves HTTPS URL/trust, not every possible iOS network policy; the actual installed PWA must be tested.

## Option B: Tailscale Funnel — public managed tunnel

```text
GitHub Pages PWA on iPhone
    → https://kindle.<tailnet>.ts.net
    → public Funnel relay → encrypted tunnel to Kindle tailscaled
    → TLS termination on Kindle → http://127.0.0.1:8088 → Page Turner
```

- Only the Kindle needs to join Tailscale; the phone can use ordinary Safari/PWA internet access.
- Funnel publishes a public HTTPS endpoint. It is not the same as enabling Tailscale or Serve.
- Funnel is a managed reverse tunnel, not an application-level command queue.
- Official docs say Funnel relay servers cannot decrypt the tunneled application traffic; TLS terminates on the device running Tailscale.
- The public browser endpoint avoids the direct HTTP/private-IP fetch path used by the failed iPhone experiment.
- It eliminates the need to write and host our own command relay.

Official limitations at research time: beta, Tailscale 1.38.3 or later, MagicDNS/HTTPS and Funnel policy authorization required, only tailnet-domain names, public ports 443/8443/10000, and non-configurable bandwidth limits. Bandwidth is unlikely to constrain page-turn messages; availability, latency, and abuse are more relevant. Current docs list Funnel on all plans; no permanent price/availability promise is implied.

**Security consequence:** Anyone can reach the public endpoint. Our token prevents authorized page turns but does not prevent traffic flooding. The four-client/two-second local server was built for a trusted LAN, not internet abuse. Before public exposure, review rate limiting, logging volume, proxy request framing/header size, resource exhaustion, and the transport's interaction with the Kindle UI. Do not expose the filesystem, token config, or general KOReader HTTP inspector. CORS is not protection against non-browser attackers.

Funnel is a change to the earlier no-public-exposure assumption. The owner has authorized research, not enabling it.

## Community Kindle integrations found

### KOReader plugin

Repository: [victoria-riley-barnett/koreader-tailscale](https://github.com/victoria-riley-barnett/koreader-tailscale)

Inspected README and selected Lua/shell source at commit `5422ff9bfe5268e34088fd81d6a774d0cca6c03f`.

- Describes installation inside KOReader and ARMv7/ARM64 support.
- README quotes approximately 57 MB download; this is **not** a measured RAM budget.
- Downloads Tailscale binaries, supports QR/auth-key login, probes KOReader's CA bundle, and offers kernel-TUN and userspace modes.
- Starts a daemon on KOReader launch and preserves the node's prior connection preference.
- Offers optional global KOReader HTTP proxy configuration and exit-node settings.
- Source can bring up loopback, accepts routes, disables Tailscale DNS acceptance, and uses `--netfilter-mode=off` in its up flags.
- Start script uses process-wide `killall tailscaled` rather than owning only a Page Turner process.

This is useful packaging precedent, **not** a verified drop-in Page Turner deployment. Avoid enabling exit nodes, accepted subnet routes, or global KOReader proxy changes simply to proxy a local API. Audit startup/shutdown/sleep/USB behavior and process ownership first. We have not validated this community code on the owner's hardware or confirmed Serve/Funnel through its UI.

### Kindle KUAL extension

Repository: [mitanshu7/tailscale_kual](https://github.com/mitanshu7/tailscale_kual)

Inspected README and selected scripts at commit `ccd35eb666d853a146dbec6f13f72346a43c5be1`.

- Supports a jailbroken Kindle with KUAL, standalone Tailscale binaries, userspace/proxy/TUN modes, and persistent node state.
- Default documented `tailscale up` options enable Tailscale SSH; remote shell access is unnecessary for Page Turner and should not be enabled by default for our use case.
- Explicitly lists older Kindle models as unsupported, including first-generation Paperwhite, Kindle Keyboard, and Kindle 4.
- Notes that ordinary Kindle sleep/Wi-Fi shutdown makes the device unreachable.

## Compatibility risks — must check before installation

1. **Kindle model, kernel, CPU architecture.** Official Tailscale static builds exist for ARM/ARM64, but unsupported Linux distributions are best-effort. CPU compatibility does not prove kernel compatibility.
2. **Stale minimum-kernel guidance.** The KUAL README says Linux 2.6.32; upstream Go 1.24 requires Linux 3.2+. Tailscale release `v1.102.4` was the latest release returned during research and its `go.mod` declares Go 1.26.6. The old README threshold is not a sufficient basis to install current binaries. Check the actual release/build and device. Do not solve this by silently pinning an old unmaintained Tailscale version.
3. **TUN and userspace mode.** Userspace networking can avoid requiring a kernel TUN interface; it does not bypass the Go runtime's kernel/CPU requirements. Verify Serve/Funnel in the selected mode on this hardware.
4. **Resources.** No trustworthy on-device RAM/CPU/battery measurement was obtained. TLS and the VPN daemon still execute on the Kindle even though our Lua plugin remains HTTP-only.
5. **Normal sleep.** Tailscale does not make a sleeping Kindle remotely usable without changing power behavior. Preserve normal sleep; return a clear offline/uncertain result and never queue/replay page turns.
6. **Persistent credentials.** Node state, account keys, and local certificate keys must be protected as practicable on Kindle storage, excluded from source control, and revocable.
7. **TLS trust bootstrapping.** Tailscale needs outbound access and a valid CA bundle. Serve/Funnel handle browser-facing certificates; they do not remove the daemon's own TLS requirements.

## Required Page Turner changes if selected

### PWA

Unlike the earlier CORS-only update, this approach **does require a small PWA change**:

- `mobile-pwa/app.js` currently accepts IPv4 literals only and rejects ports below 1024.
- Support the selected trusted HTTPS hostname and standard port 443 (preferably a validated endpoint URL).
- Keep credentials out of URLs, logs, caches, and service-worker command handling.
- Retain one-shot requests, honest errors, and the existing foreground wake-lock lifecycle.

### Plugin and deployment

- Keep authenticated POST `/next` and `/back` plus Pages-origin CORS.
- Tailscale Serve/Funnel can proxy to `127.0.0.1:8088`; our Lua server need not implement HTTPS.
- Consider a loopback-only bind and removal of LAN firewall openings **for a deliberate tunnel-only mode**, while preserving the currently working LAN mode for rollback. Existing code binds all interfaces.
- Test proxy-added headers against the strict parser and 4 KiB limit; test bodyless POST framing, OPTIONS, errors, and disconnects.
- Do not assume intermediaries provide exactly-once delivery. Test lost acknowledgement/reconnect and keep no-retry semantics; evaluate command IDs if needed.
- Treat VPN/tunnel deployment as a separate, reversible component. Preserve normal reader navigation, settings, Wi-Fi, and sleep.

## Recommendation and next approval

**First evaluate compatibility, then prefer Serve if installing Tailscale on the iPhone is acceptable.** It avoids publicly exposing the page-turn listener. If the desired outcome is specifically a public HTTPS endpoint with no phone VPN app, **Funnel is the relevant feature**, but it needs explicit public-exposure approval and hardening before deployment.

No installation, login, certificate issuance, VPN configuration, public endpoint, firmware query, or Page Turner implementation change was performed during this research. Only public documentation/source and existing local code were inspected.

Before the next check, ask the owner for the Kindle model and approval to obtain read-only kernel/architecture/resource information. Also ask whether a phone Tailscale app is acceptable (Serve) or the endpoint must work without it (Funnel). Internet during reading is now accepted; PWA and wake lock remain required.

## Sources

- [Tailscale overview](https://tailscale.com/kb/1151/what-is-tailscale)
- [Serve](https://tailscale.com/kb/1312/serve) and [Serve CLI](https://tailscale.com/kb/1242/tailscale-serve)
- [Funnel](https://tailscale.com/kb/1223/funnel)
- [HTTPS and certificate lifecycle](https://tailscale.com/kb/1153/enabling-https): plain HTTP over Tailscale is still HTTP to browsers; managed Serve differs from manually exporting certificate files. Machine FQDNs appear in public Certificate Transparency logs even for private Serve.
- [Static Linux binaries](https://tailscale.com/kb/1053/install-static)
- [Userspace networking](https://tailscale.com/kb/1112/userspace-networking)
- [iOS installation](https://tailscale.com/kb/1020/install-ios)
- [KOReader community plugin, inspected revision](https://github.com/victoria-riley-barnett/koreader-tailscale/tree/5422ff9bfe5268e34088fd81d6a774d0cca6c03f)
- [KUAL community extension, inspected revision](https://github.com/mitanshu7/tailscale_kual/tree/ccd35eb666d853a146dbec6f13f72346a43c5be1)
- [KUAL first-generation Paperwhite incompatibility report](https://github.com/mitanshu7/tailscale_kual/issues/24)
- [Go 1.24 Linux minimum](https://go.dev/doc/go1.24#linux)
- [Tailscale v1.102.4 go.mod](https://github.com/tailscale/tailscale/blob/v1.102.4/go.mod)
