# Architecture

MacBook Stereo Pair separates the system into a required runtime and an optional
browser controller. This repository owns everything on the audio path.

```text
macOS applications
       |
       v
BlackHole 2ch output
       |
       | PortAudio / CoreAudio HAL
       | 10 ms capture callbacks
       v
snapcast-capture-blackhole
       |
       +---- left.pcm FIFO ----> Snapserver LeftAudio
       |
       +---- right.pcm FIFO ---> Snapserver RightAudio

LeftAudio  -> role-based left client  -> CoreAudio -> left MacBook speaker
RightAudio -> role-based right client -> CoreAudio -> right MacBook speaker
```

## Capture and Split

BlackHole is a virtual CoreAudio output device. PortAudio opens it as an input
and receives 48 kHz, 32-bit float samples in 10 ms callbacks. Each callback is
converted once into two mono 24-bit PCM buffers. The left and right buffers are
written by the same process from the same callback, preserving a shared source
clock and block boundary.

The splitter writes to two named pipes:

```text
~/Library/Application Support/Snapcast/run/left.pcm
~/Library/Application Support/Snapcast/run/right.pcm
```

Snapserver reads the FIFOs as `LeftAudio` and `RightAudio`. Both streams use
uncompressed PCM at `48000:24:1`, with `chunk_ms = 20` and `buffer = 200`.
The PCM payload is approximately 192,000 bytes/s or 1.54 Mbit/s per stream,
before TCP and Snapcast protocol overhead.

## Synchronization

One capture process creates both channels, so no independent application
clocks can drift before Snapserver. Snapcast timestamps encoded chunks using
the server clock. Both clients use that clock to schedule the first sample and
correct small clock differences by inserting or removing samples.

Synchronization aligns the playback timelines at each client. It cannot remove
the speed-of-sound delay between speakers separated across a room. Physical
placement, relative volume, and room acoustics still affect the perceived
stereo image and echo.

The 200 ms stream buffer absorbed Wi-Fi scheduling jitter in the validated
setup. Lower buffers reduce latency but increase the chance of underruns.

## Local Output Binding

In snapcast mode, the source Mac's default system output must be BlackHole so
applications are captured. The local Snapclient therefore cannot follow the
system default output without creating feedback or silence.

The patched CoreAudio player reads `SNAPCLIENT_COREAUDIO_DEVICE` and selects that
device explicitly. The default is `BuiltInSpeakerDevice`. A mono Snapcast
stream is duplicated into both channels of the local AudioQueue output.

BlackHole and the built-in speaker expose separate CoreAudio volume controls.
The runtime helper resolves both by UID and sets each virtual main volume to
100%. This prevents the BlackHole output slider from silently attenuating the
signal before capture while the independently selected local speaker remains at
a different hardware level.

Treat Snapcast volume as the normal listening control. The macOS volume slider
for BlackHole is a capture-level control and is normalized back to 100% while
the pair runtime is active.

## Groups and Roles

The pair uses stable role IDs rather than IP-derived names:

```text
LOCAL_CLIENT_ID=stereo-local
REMOTE_CLIENT_ID=stereo-remote
```

`LEFT_IS_REMOTE` maps those roles onto the physical stage:

- `true`: remote client receives `LeftAudio`, local client receives
  `RightAudio`.
- `false`: local client receives `LeftAudio`, remote client receives
  `RightAudio`.

`ensure-pair-routing.sh` runs every 15 seconds. If both clients join one
Snapcast group, it branches the right client into a separate group. It then
ensures the resolved clients are connected to their expected streams without
changing user-defined names, volume, mute state, or latency.

The controller follows the stream IDs, not client IDs. Any connected client in
the `LeftAudio` group is displayed and treated as the left side; the
`RightAudio` group determines the right side.

## Recovery

Snapserver opens both FIFOs for reading and retries after EOF. If the splitter
exits, both streams become idle until launchd restarts it. If Snapserver
restarts, an in-flight FIFO write can fail, causing the splitter to exit and be
relaunched after the server's new readers are ready.

The process source accepts scheduling jitter below 200 ms by reading again
while preserving the logical audio timeline. A gap of 200 ms or more is treated
as a genuine discontinuity and triggers a real resync.

## Network Boundary

Snapserver binds the control APIs to `127.0.0.1`:

```text
HTTP:        127.0.0.1:1780
TCP control: 127.0.0.1:1705
```

The PCM stream port binds to the network at `0.0.0.0:1704` and has no built-in
authentication. A trusted LAN, VPN, or restrictive firewall is required.
