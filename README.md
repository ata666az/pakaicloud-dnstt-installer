# PakaiCloud DNSTT Installer

One-command installer for the **DNSTT server** on Ubuntu 24.04 LTS, tuned for PakaiCloud NAT VPS.

- Default tunnel zone: `ata.jijah.loc.cc`
- Default DNSTT UDP listener: `21092`
- Default TCP upstream: `127.0.0.1:22`
- Service: `dnstt-server` (systemd)
- Source: upstream DNSTT project at https://www.bamsoftware.com/git/dnstt.git

> This repository contains installer code and documentation only. Never commit VPS backups, `server.key`, credentials, or other secrets.

## One-command installation

Run as root:

```bash
curl -fsSL https://raw.githubusercontent.com/ata666az/pakaicloud-dnstt-installer/main/install.sh | bash
```

Or with sudo:

```bash
curl -fsSL https://raw.githubusercontent.com/ata666az/pakaicloud-dnstt-installer/main/install.sh | sudo bash
```

Review `install.sh` before piping a remote script into a root shell.

## Custom settings

Defaults are `ata.jijah.loc.cc`, UDP `21092`, and `127.0.0.1:22`. Override them with:

```bash
curl -fsSL https://raw.githubusercontent.com/ata666az/pakaicloud-dnstt-installer/main/install.sh | sudo bash -s -- custom.example.com 21092 127.0.0.1:22
```

Arguments: `ZONE`, `UDP_PORT`, and loopback `UPSTREAM`.

## DNS and NAT

The installer binds DNSTT to the local UDP port only. Configure provider NAT forwarding separately. For conventional DNS-based DNSTT, public UDP 53 must reach the authoritative server. For a direct/custom UDP client, the client must support an explicit custom UDP endpoint and the provider must forward the selected public UDP port to this VPS.

Use `ata.jijah.loc.cc` as the tunnel zone. `ns-ata.jijah.loc.cc` is a nameserver hostname, not the tunnel zone.

## Client information

After installation, inspect `/root/dnstt-client-info.txt`. Only the public key belongs in client settings. Never publish `/etc/dnstt/server.key`.

## Verify

```bash
systemctl status dnstt-server --no-pager
journalctl -u dnstt-server -n 50 --no-pager
ss -lunp | grep ':21092'
```

## Scope and safety

- Ubuntu 24.04 LTS only.
- Does not modify SSH settings, passwords, SSH accounts, firewall rules, DNS records, or provider NAT mappings.
- Does not install Xray/VLESS.
- Runs DNSTT under a dedicated unprivileged service account.

## License

MIT. See [LICENSE](LICENSE). The upstream DNSTT project is maintained separately and retains its own license.
