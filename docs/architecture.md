# Architecture

MacBook Stereo Pair is a self-contained macOS runtime with a native SwiftUI
control console. This repository owns everything on the audio path and all
supported control surfaces.

```text
MacStereoPair.app ─┐
                   ├─ owner-only Unix socket ─ StereoPairAgent
mac-stereo-pairctl ┘                           ├─ launchctl
                                               ├─ Snapserver JSON-RPC
                                               └─ shared audio meters
```

The Agent and GUI are control-plane processes. Audio capture, Snapserver, and
both Snapclients remain independent launchd jobs. Closing or crashing the GUI
does not interrupt playback.

```text
macOS applications
       |
       v
BlackHole 2ch output
       |
       | CoreAudio IOProc callbacks
       v
lock-free stereo ring
       |
       | continuous 10 ms writer
       v
snapcast-capture-blackhole
       |
       +---- left.pcm FIFO ----> Snapserver LeftAudio
       |
       +---- right.pcm FIFO ---> Snapserver RightAudio

LeftAudio  -> role-based left client  -> CoreAudio -> left MacBook speaker
RightAudio -> role-based right client -> CoreAudio -> right MacBook speaker
```

## 1. Capture and Split

BlackHole is a virtual CoreAudio output device. A CoreAudio HAL IOProc receives
48 kHz, 32-bit float samples and places them in a bounded single-producer,
single-consumer ring without allocating, logging, or writing files in the
real-time callback. The left and right channels come from the same frame stream,
preserving a shared source clock and block boundary.

An independent writer emits exactly 480 frames every 10 ms. When a complete
block is available it converts that block to two mono 24-bit PCM buffers; when
the device is idle it writes zero-valued digital silence. A backlog older than
50 ms is discarded in favour of fresh input. The continuous 10 ms writer keeps
the FIFO and Snapserver timeline alive across periods when BlackHole has no
application audio.

The splitter writes to two named pipes:

```text
~/Library/Application Support/Snapcast/run/left.pcm
~/Library/Application Support/Snapcast/run/right.pcm
```

Snapserver reads the FIFOs as `LeftAudio` and `RightAudio`. Both streams use
uncompressed PCM at `48000:24:1`, with `chunk_ms = 20` and `buffer = 200`.
The PCM payload is approximately 192,000 bytes/s or 1.54 Mbit/s per stream,
before TCP and Snapcast protocol overhead.

## 2. Placement and Acoustic Limits

Place both Macs symmetrically around the primary listening position. Equal
distance, height, orientation, and nearby room boundaries matter more than a
very precise absolute distance. A near-equilateral triangle between the two
Macs and the listener is a useful starting point, followed by small adjustments
using centered vocals and hard-panned material.

Keep both Snapcast channel levels equal and both physical output stages at 100%.
One-sided walls, corners, furniture, or reflective surfaces can still pull the
center image toward one side.

## 3. Synchronization

One capture process creates both channels, so no independent application
clocks can drift before Snapserver. Snapcast timestamps encoded chunks using
the server clock. Both clients use that clock to schedule the first sample and
correct small clock differences by inserting or removing samples.

Synchronization aligns the playback timelines at each client. It cannot remove
path-length delay, reflections, or other acoustic asymmetry between the two
speakers. Placement, relative volume, and room acoustics still affect the
perceived stereo image and echo.

The 200 ms stream buffer absorbed Wi-Fi scheduling jitter in the validated
setup. Lower buffers reduce latency but increase the chance of underruns.

## 4. Local Output Binding

In snapcast mode, the source Mac's default system output must be BlackHole so
applications are captured. The local Snapclient therefore cannot follow the
system default output without creating feedback or silence.

The patched CoreAudio player reads `SNAPCLIENT_COREAUDIO_DEVICE` and selects that
device explicitly. The default is `BuiltInSpeakerDevice`. A mono Snapcast
stream is duplicated into both channels of the local AudioQueue output.

BlackHole and the built-in speaker expose separate CoreAudio volume controls.
The runtime helper resolves both by UID and sets the virtual main volume
(`vmvc`) and physical main-volume scalar (`volm`) to 100%. This prevents the
BlackHole output slider from silently attenuating the signal before capture
while the independently selected local speaker remains at a different hardware
level.

Treat Snapcast volume as the normal listening control. The macOS volume slider
for BlackHole is a capture-level control and is normalized back to 100% while
the pair runtime is active.

Before entering Snapcast mode, each Mac records its current physical output UID,
name, and exact volume in `state/native-audio.json`. When returning audio to
macOS, the runtime applies the saved volume to that device before changing the
default output. If the saved device is unavailable, it uses the built-in
speaker at a conservative 30%, never 100% by default.

The CoreAudio player applies the exponential Snapcast volume curve through
`AudioQueueSetParameter(kAudioQueueParam_Volume)`. This keeps the received
24-bit buffer at full scale and lets CoreAudio perform the attenuation in its
floating-point playback path. Hardware output volume remains at 100%.

## 5. Groups and Roles

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

The native console follows the stream IDs, not client IDs. Any connected client
in the `LeftAudio` group is displayed and treated as the left side; the
`RightAudio` group determines the right side.

## 6. Recovery

Snapserver opens both FIFOs for reading and retries after EOF. Ordinary idle
BlackHole periods do not close either FIFO: the writer continues emitting
digital silence. If the splitter exits unexpectedly, both streams become idle
until launchd restarts it. If Snapserver restarts, the capture writer keeps its
clock running and reopens an affected FIFO when the new reader is ready.

The capture supervisor treats the CoreAudio callback heartbeat as the device
health signal. After two seconds without callbacks it recreates the IOProc while
the writer continues silence. Repeated failure to recover callbacks for fifteen
seconds is the last-resort process exit; missing audio samples alone never
trigger a relaunch.

On macOS, Snapserver keeps both FIFO ends open for read mode. This avoids an
immediate EOF/close cycle when Snapserver starts before the splitter writer,
which otherwise can leave both processes retrying without establishing a
connection.

The process source accepts scheduling jitter below 200 ms by reading again
while preserving the logical audio timeline. A gap of 200 ms or more is treated
as a genuine discontinuity and triggers a real resync.

Both Macs run a lightweight user LaunchAgent that listens for the macOS
power-on notification. After CoreAudio has settled, the source Mac restores
BlackHole routing, normalizes both source hardware volumes, and recreates the
capture and local playback processes. The remote Mac normalizes its speaker and
recreates Snapclient. This avoids reusing AudioQueues that macOS invalidated
during sleep.

## 7. Network Boundary

Snapserver binds the control APIs to `127.0.0.1`:

```text
HTTP:        127.0.0.1:1780
TCP control: 127.0.0.1:1705
```

The PCM stream port binds to the network at `0.0.0.0:1704` and has no built-in
authentication. A trusted LAN, VPN, or restrictive firewall is required.
