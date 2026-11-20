# Troubleshooting

Start with:

```sh
./integration/scripts/check-health.sh
```

## Missing LeftAudio or RightAudio

Confirm the stream format:

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

## FIFO Errors

Check the named pipes:

```sh
ls -l "$HOME/Library/Application Support/Snapcast/run"
```

Both `left.pcm` and `right.pcm` should be FIFOs owned by the current user. If
either is missing, rerun:

```sh
./integration/scripts/install-local.sh
```

Do not replace a FIFO with a regular file. A leftover splitter process can also
hold a stale endpoint after server recovery; restart both services in the
order shown above.

## Streams Are Reversed

Open:

```text
~/.config/snapcast-stereo-pair/pair.env
```

Set `LEFT_IS_REMOTE` to match physical placement:

- `true` means the remote Mac is on the left.
- `false` means the source Mac is on the left.

Then reinstall the local runtime so templates and routing use the new roles:

```sh
./integration/scripts/install-local.sh
```

The controller derives the visible sides from `LeftAudio` and `RightAudio`, not
from client IDs.

## Local MacBook Is Silent

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

## Dropouts or Periodic Gaps

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
- The remote Mac is not suspending the LaunchAgent during sleep.

If the network genuinely needs a larger buffer, change `buffer` in
[`integration/config/snapserver.conf.in`](../integration/config/snapserver.conf.in)
and rerun the local installer. A smaller buffer increases underrun risk.

## Audio/Video Offset

Snapcast synchronization aligns the two audio clients with each other. The
stream buffer adds intentional latency between the source application and both
speakers.

Keep both sides on the same runtime configuration and the same buffer. Changing
one client's latency can improve a specific room compromise but breaks the
left/right timing relationship.

## Return to Native Audio

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
the server stopped, the remote client has no stream to play.

## Collect a Safe Bug Report

Include:

- Runtime and controller release tags.
- Mac model, CPU architecture, and macOS version.
- BlackHole version.
- Exact reproduction steps.
- Redacted logs from around the failure.

Do not post IP addresses, usernames, SSH details, credentials, `pair.env`, full
home paths, or unredacted logs in a public issue.

