# Contributing

Thank you for improving MacBook Stereo Pair for macOS.

## Repository Scope

This repository owns capture, streams, Snapserver, Snapclients, launchd
services, installation, device recovery, the native SwiftUI console, and the
control Agent.

## Development

For the runtime:

```sh
./integration/scripts/build-macos.sh
integration/test/test-pair-config.sh
integration/test/test-pair-routing.sh
zsh -n integration/scripts/*.sh integration/test/*.sh
plutil -lint integration/launchagents/*.plist.in
```

Use the installed native application for manual UI acceptance. Hardware changes
also require a two-MacBook validation report.

[AGENTS.md](AGENTS.md) contains the canonical complete release-check list. Run
the checks that cover the change and use the complete list before a release.

## Pull Requests

- Explain the user-visible problem and the chosen behavior.
- Keep unrelated changes out of the pull request.
- Add tests before changing production behavior.
- State whether audio quality, latency, routing, CPU, or network behavior
  changes.
- List manual hardware and native UI checks.
- Keep commits focused and reproducible.
- Do not commit generated builds, logs, local configuration, or editor state.

## Bug Reports

Include runtime and native console versions, Mac model, CPU architecture, macOS
version, BlackHole version, reproducer, expected behavior, actual behavior, and
minimal redacted logs.

Never include IP addresses, usernames, SSH credentials, passwords, private
keys, tokens, `pair.env`, or full home-directory paths. Replace network values
with documentation-reserved examples before posting.

## Licensing

By submitting a contribution, you agree that it may be distributed under
GPL-3.0-or-later. Preserve all applicable upstream copyright notices and
attribution.

## Conduct

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
