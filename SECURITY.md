# Security Policy

## Supported Versions

Security fixes target the current `v0.1.x` source release and the `main`
branch. Older preparation branches and private development branches are not
supported releases.

## Reporting a Vulnerability

Use this repository's GitHub private security advisory feature:

```text
https://github.com/damoqiongqiu/snapcast-stereo-pair/security/advisories/new
```

Do not open a public issue for an undisclosed vulnerability. Include the
affected release, macOS version, reproduction steps, impact, and the minimum
redacted evidence needed to investigate.

## Trusted Network Boundary

Snapcast TCP stream port `1704` has no built-in authentication. Deployments
must use a trusted LAN or a trusted VPN/firewall. Never expose the stream port
directly to the public internet.

The runtime binds Snapserver HTTP and TCP control to localhost by default.
Interactive control surfaces do not include application-level authentication
and should not be exposed publicly.

## Sensitive Data

Never post IP addresses, usernames, SSH details, passwords, private keys,
tokens, unredacted logs, `pair.env`, or full home-directory paths in a public
issue, discussion, pull request, or security report body that will be made
public.

## Scope

Reports about upstream Snapcast vulnerabilities should also be shared with the
upstream project through its documented security channel. Reports about the
optional controller should use:

```text
https://github.com/damoqiongqiu/snapweb-stereo-pair/security/advisories/new
```

