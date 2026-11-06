# Installation notes

## Requirements

- Ubuntu 24.04 LTS.
- Root or sudo access.
- A local TCP service at the configured upstream (default SSH at `127.0.0.1:22`).
- Provider-side UDP NAT forwarding configured separately.

## PakaiCloud NAT example

| Public endpoint | VPS endpoint | Service |
|---|---|---|
| `PUBLIC_IP:21091/TCP` | `PRIVATE_IP:22/TCP` | SSH |
| `PUBLIC_IP:21092/UDP` | `PRIVATE_IP:21092/UDP` | DNSTT direct/custom UDP |

The installer binds DNSTT to the local UDP port. It cannot create or verify provider-side NAT mappings.

## Key migration

A clean install creates a new keypair. To preserve a tunnel identity when migrating servers, securely transfer both `server.key` and `server.pub` to `/etc/dnstt/` before running the installer. Keep the private key secret and never upload it to GitHub.

## Client

Use tunnel zone `ata.jijah.loc.cc` and the public key printed in `/root/dnstt-client-info.txt`. Replace `PUBLIC_IP` with the public gateway address. The SSH endpoint is separate from the DNSTT UDP endpoint.
