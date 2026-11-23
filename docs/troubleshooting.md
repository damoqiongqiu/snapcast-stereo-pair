# Troubleshooting

Start with:

```sh
./integration/scripts/check-health.sh
```

The native console and CLI share the same Agent snapshot. Use Advanced
Diagnostics for redacted export, service state, versions, and logs:

```sh
~/Library/Application\ Support/Snapcast/bin/mac-stereo-pairctl status
```

## 1. Missing LeftAudio or RightAudio

Confirm the stream format:

The native console treats a client as offline when its Snapserver heartbeat is
older than six seconds. A red channel card and cleared waveform therefore mean
the remote Mac stopped reporting before the TCP connection necessarily closed.

```sh
curl -fsS http://127.0.0.1:1780/jsonrpc \
  -H 'Content-Type: application/json' \
  --data '{"id":1,"jsonrpc":"2.0","method":"Server.GetStatus"}' |
  jq '.result.server.streams[] | {id, sampleformat: .uri.query.sampleformat}'
```

Both streams must exist at `48000:24:1`. If the server is unavailable, inspect:

```text
~/Library/Logs/Snapcast/server.log
~/Library/Logs/Snapcast/splitter.stderr.log
```

Restart the server and splitter:

```sh
uid="$(id -u)"
launchctl kickstart -k "gui/$uid/com.snapcast.server"
launchctl kickstart -k "gui/$uid/com.snapcast.splitter"
```

## 2. FIFO Errors

Check the named pipes:

```sh
ls -l "$HOME/Library/Application Support/Snapcast/run"
```

Both `left.pcm` and `right.pcm` should be FIFOs owned by the current user. If
either is missing, rerun:

```sh
./integration/scripts/install-product.sh --force-reinstall
```

Do not replace a FIFO with a regular file. A leftover splitter process can also
hold a stale endpoint after server recovery; restart both services in the
order shown above.

## 3. Streams Are Reversed

Open:

```text
~/.config/snapcast-stereo-pair/pair.env
```

Set `LEFT_IS_REMOTE` to match physical placement:

- `true` means the remote Mac is on the left.
- `false` means the source Mac is on the left.

Then reinstall the local runtime so templates and routing use the new roles:

```sh
./integration/scripts/install-product.sh --force-reinstall
```

The native console derives the visible sides from `LeftAudio` and `RightAudio`, not
from client IDs.

If routing is correct but the center image remains offset, check the physical
layout described in
[Physical Placement](../README.md#32-physical-placement).

## 4. Local MacBook Is Silent

In snapcast mode, the system output is BlackHole and applications are suspended
from the speaker. The local Snapclient must select the built-in speaker
explicitly.

Verify:

```sh
SwitchAudioSource -c -t output
launchctl print "gui/$(id -u)/com.snapcast.local-client"
```

The current system output should be `BlackHole 2ch`, and the local client should
be running with `SNAPCLIENT_COREAUDIO_DEVICE` set. If the configured device UID
is wrong, run `SwitchAudioSource -a -t output`, update
`LOCAL_OUTPUT_DEVICE`, and reinstall.

## 5. One Side Is Much Quieter

Run:

```sh
./integration/scripts/check-health.sh
```

Both hardware volume lines must report `100.00%`. BlackHole and the built-in
speaker are separate CoreAudio devices: changing the macOS volume while
BlackHole is selected does not change the speaker's hardware level.

The volume helper writes both the virtual main volume (`vmvc`) and the physical
main volume scalar (`volm`). Health checks report the lower of the two supported
controls, because macOS can restore them independently after wake.

Reapply the normalization:

```sh
"$HOME/Library/Application Support/Snapcast/route-audio.sh"
```

The runtime also reapplies this calibration while routing is active. Use the
console's volume after the hardware stages are normalized.

The console volume is applied by CoreAudio after the 24-bit PCM chunks have
been decoded. The stream itself remains at full scale; lowering Snapcast volume
does not rewrite or truncate the integer audio buffers.

If both Snapcast and hardware levels match, compare speaker distance, nearby
walls, furniture, and Mac orientation before compensating with channel volume.

## 6. Crackling, Dropouts, or Low Volume After Wake

macOS can invalidate active CoreAudio queues during sleep and restore the
speaker's physical volume separately from its virtual main volume. Both Macs
therefore install a user wake-recovery service.

Verify that it is running:

```sh
launchctl print "gui/$(id -u)/com.snapcast.wake-recovery"
```

The service waits briefly for CoreAudio to settle, re-selects BlackHole on the
source Mac, writes both volume controls, and recreates the audio processes.
The remote installer installs the equivalent service as
`com.snapcast.remote-wake-recovery`.

If a failure still occurs, collect
`~/Library/Logs/Snapcast/wake-recovery.stderr.log` and any `snapclient` crash
report produced around the wake time.

## 7. Dropouts or Periodic Gaps

The validated 200 ms buffer covers normal Wi-Fi jitter. Symptoms include
`Not enough`, `age >`, `No chunk available`, or `onResync` in recent logs.

Check the pair before changing settings:

```sh
./integration/scripts/check-health.sh
```

Also check:

- Both Macs remain on a stable LAN or VPN.
- Only one Snapserver is running on the source Mac.
- The selected source address is reachable from the remote Mac.
- No duplicate Snapclient processes use the same role ID.
- The wake-recovery LaunchAgents are running on both Macs.

If the network genuinely needs a larger buffer, change `buffer` in
[`integration/config/snapserver.conf.in`](../integration/config/snapserver.conf.in)
and rerun the local installer. A smaller buffer increases underrun risk.

## 8. Audio/Video Offset

Snapcast synchronization aligns the two audio clients with each other. The
stream buffer adds intentional latency between the source application and both
speakers.

Keep both sides on the same runtime configuration and the same buffer. Changing
one client's latency can improve a specific room compromise but breaks the
left/right timing relationship.

## 9. Return to Native Audio

Choose **Mac system audio** in the native console or use the command below.
System mode intentionally stops the pair runtime.

Use the generated mode switcher:

```sh
~/Library/Application\ Support/Snapcast/set-mode.sh native
```

This stops and disables local services and restores the configured native output
UID. To resume the pair:

```sh
~/Library/Application\ Support/Snapcast/set-mode.sh snapcast
```

The local script does not modify the remote Mac's installed LaunchAgent. With
the server stopped, the remote client has no stream to play. The native Agent
attempts a bounded, key-only remote stop and reports a degraded warning when the
remote Mac is unavailable without rolling back the local switch.

Running `set-mode.sh` directly changes only the local Mac. Use the native console
or `mac-stereo-pairctl stop` when coordinated best-effort remote mode handling is
required.

Expected disabled services in system mode do not generate notifications. A
notification is sent once when Snapserver, a playback route, a client, or wake
recovery actually fails in Snapcast mode, then resets after recovery.

Each Mac stores its pre-Snapcast physical output and exact volume at:

```text
~/Library/Application Support/Snapcast/state/native-audio.json
```

Both Macs restore that volume before switching output back. If the remembered
device is unavailable, the fallback volume is 30%. Do not raise the saved
fallback to 100%; use the normal system volume after the transition.

## 10. Collect a Safe Bug Report

Include:

- Runtime and native console release tags.
- Mac model, CPU architecture, and macOS version.
- BlackHole version.
- Exact reproduction steps.
- Redacted logs from around the failure.

Do not post IP addresses, usernames, SSH details, credentials, `pair.env`, full
home paths, or unredacted logs in a public issue.

