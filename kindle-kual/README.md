# Kindle KUAL utilities

## Page Turner Tunnel compatibility check

This check collects the minimum system information needed to decide whether a maintained Tailscale binary can run on the target Kindle. It does not install or run Tailscale, change networking, or collect CPU serial, books, Wi-Fi details, credentials, or Page Turner tokens.

1. Connect the Kindle over USB.
2. Copy the folder [`pageturner-tunnel`](pageturner-tunnel/) into the Kindle's `extensions` folder. The resulting path must be:

   ```text
   /mnt/us/extensions/pageturner-tunnel/menu.json
   ```

3. Safely eject the Kindle.
4. Open KUAL → **Page Turner Tunnel** → **Check compatibility**.
5. Wait for the success message.
6. Reconnect USB and copy this report back to the computer:

   ```text
   /mnt/us/pageturner-compatibility.txt
   ```

7. Share the report for review. It is designed to omit device serial numbers and application secrets, but you may inspect it before sharing.

To remove the diagnostic, delete `/mnt/us/extensions/pageturner-tunnel/` and `/mnt/us/pageturner-compatibility.txt`. No system files are changed.

## Current Tailscale launch test

The prepared local package includes the official Tailscale 1.102.4 32-bit ARM binaries. The downloaded archive was verified against the SHA-256 checksum published by Tailscale; details are in `pageturner-tunnel/bin/PROVENANCE.txt`.

This test only invokes `tailscale version` and `tailscaled --version`, with a 15-second limit when the Kindle provides the `timeout` command. It does not start the daemon, create node state, log in, or enable Funnel.

1. Replace the earlier `/mnt/us/extensions/pageturner-tunnel/` folder with the newly prepared folder, including its `bin` directory. Do not merge it with the old copy because a failed copy could leave a partial binary.
2. Safely eject the Kindle and reopen KUAL.
3. Select **Page Turner Tunnel → Test current Tailscale launch** once.
4. Reconnect USB and retrieve:

   ```text
   /mnt/us/pageturner-tailscale-launch-test.txt
   ```

5. Share that report for review.

After the test, the extension can be removed using the instructions above. Also delete `/mnt/us/pageturner-tailscale-launch-test.txt` if no longer needed.

## Temporary daemon test

After the launch test passes, the temporary daemon test starts `tailscaled` for approximately 15 seconds with:

- userspace networking (no TUN device required),
- ephemeral in-memory state,
- no login or auth key,
- no Serve or Funnel configuration, and
- Tailscale support-log uploads disabled for the test.

It checks the local API socket, records selected process memory/thread metrics, classifies daemon errors without copying raw logs into the report, and then stops only the process it started. Temporary state, socket, and log files are removed.

1. Copy the updated `pageturner-tunnel/scripts/test-tailscaled-daemon.sh` and `pageturner-tunnel/menu.json` to their matching paths under `/mnt/us/extensions/pageturner-tunnel/`. The existing binaries do not need to be copied again.
2. Safely eject and reopen KUAL.
3. Select **Page Turner Tunnel → Test temporary Tailscale daemon** once and wait roughly 20 seconds.
4. Reconnect USB and retrieve:

   ```text
   /mnt/us/pageturner-tailscaled-daemon-test.txt
   ```

5. Share that report for review.

## Register the Kindle with a private tailnet

This uses a one-off auth key; it does not put the Tailscale account password on the Kindle. Registration creates persistent node identity in `pageturner-tunnel/state/`. The scripts do not enable Tailscale SSH, exit nodes, accepted routes, or Tailscale DNS.

1. In the [Tailscale admin console Keys page](https://login.tailscale.com/admin/settings/keys), choose **Generate auth key** with:
   - **Reusable:** off (one-off)
   - **Ephemeral:** off
   - **Pre-approved:** on, if shown
   - **Expiration:** 1 day
   - **Tags:** none
2. Copy the key once. Never paste it into source control, chat, a screenshot, or a URL.
3. On the computer, create a plain-text file named `auth.key` containing only the key on one line.
4. Copy the updated `menu.json` and these scripts into their matching Kindle paths:
   - `scripts/start-private-tailscale.sh`
   - `scripts/register-private-tailscale.sh`
   - `scripts/status-private-tailscale.sh`
   - `scripts/stop-private-tailscale.sh`
5. Create this Kindle folder if needed, then copy the key to the exact path:

   ```text
   /mnt/us/extensions/pageturner-tunnel/private/auth.key
   ```

6. Safely eject and reopen KUAL.
7. Select **Page Turner Tunnel → Register Kindle with auth key** once. This starts the isolated userspace daemon, registers it as `pageturner-kindle`, and deletes `auth.key` only after successful registration. A one-off key is automatically revoked after use.
8. Select **Show private Tailscale status**. The Kindle should also appear on the admin console's Machines page.
9. If registration fails, do not share `private/auth.key` or an unreviewed `logs/register.log`. The key is retained for a retry.

**Start private Tailscale** reconnects using persistent node state; no auth key is needed after registration. **Stop private Tailscale** stops only the daemon owned by this extension and preserves node state for the next test. It does not log the node out or remove it from the tailnet.

`Show private Tailscale status` displays briefly through KUAL and, in the updated script, also writes `/mnt/us/extensions/pageturner-tunnel/logs/status.log`.

## Configure private HTTPS Serve

Serve is private to authorized tailnet devices. These scripts do not run `tailscale funnel` or create a public endpoint.

1. Copy the updated `menu.json` and these scripts to matching paths on the Kindle:
   - `scripts/start-private-tailscale.sh`
   - `scripts/status-private-tailscale.sh`
   - `scripts/configure-private-serve.sh`
   - `scripts/status-private-serve.sh`
   - `scripts/disable-private-serve.sh`
2. Start Page Turner in KOReader with a book foregrounded; it must listen on port 8088.
3. In KUAL, select **Configure private HTTPS Serve** once. The action starts/reuses the registered Tailscale daemon, shows a live 15-second reconnection wait, resets old Serve configuration with a 15-second limit, and starts HTTPS setup. Running **Start private Tailscale** separately first is valid but no longer required.
4. First-time HTTPS enablement is interactive in Tailscale 1.102.4: the CLI can print an admin URL and wait. The script displays `HTTPS approval required`, the URL split across Kindle screen lines, and a two-minute counter. Open that URL while signed into Tailscale. Success displays the private endpoint; failure and connection/Serve timeouts are explicit. Detailed timestamped output remains in `logs/serve-configure.log`.
5. Select **Show private Serve status**. The Kindle immediately shows that it is checking, updates a 15-second wait counter, then shows active/not configured/failed/timeout plus the private HTTPS URL and local proxy target when active. Timestamped output is saved to `logs/serve-status.log`.
6. Keep Tailscale connected on the iPhone and open the displayed HTTPS URL with `/next` appended. A browser GET has no bearer token, so expected proof of private HTTPS reachability is HTTP 401—not a page turn.

The persistent daemon launch supplies both the explicit `state/tailscaled.state` file and `--statedir=state`. Tailscale requires the latter writable root for managed certificate storage; without it, Serve can appear active while every client handshake fails with `no TailscaleVarRoot`. After updating `start-private-tailscale.sh`, stop the already-running daemon once before configuring Serve again so the new launch argument takes effect. This preserves the registered node state.

**Disable private Serve** removes the node's Serve configuration. It does not stop Tailscale or remove node registration.
