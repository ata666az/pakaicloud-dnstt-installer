#!/usr/bin/env bash
set -Eeuo pipefail

# PakaiCloud DNSTT installer for Ubuntu 24.04 LTS.
# Usage: sudo bash install.sh [ZONE] [UDP_PORT] [UPSTREAM]
# Defaults: ata.jijah.loc.cc 21092 127.0.0.1:22

readonly DEFAULT_ZONE="ata.jijah.loc.cc"
readonly DEFAULT_PORT="21092"
readonly DEFAULT_UPSTREAM="127.0.0.1:22"
readonly SOURCE_REPO="https://www.bamsoftware.com/git/dnstt.git"
readonly SERVICE_FILE="/etc/systemd/system/dnstt-server.service"
readonly ENV_FILE="/etc/dnstt/dnstt.env"
readonly KEY_FILE="/etc/dnstt/server.key"
readonly PUB_FILE="/etc/dnstt/server.pub"
readonly BIN_FILE="/usr/local/bin/dnstt-server"
readonly INFO_FILE="/root/dnstt-client-info.txt"
readonly BUILD_INFO="/usr/local/share/pakaicloud-dnstt/build-info.txt"

ZONE="${1:-$DEFAULT_ZONE}"
DNS_PORT="${2:-$DEFAULT_PORT}"
UPSTREAM="${3:-$DEFAULT_UPSTREAM}"
TMP_DIR=""

log() { printf '\n[%s] %s\n' "$(date '+%F %T')" "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
cleanup() { [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"; }
trap cleanup EXIT

usage() {
  cat <<USAGE
PakaiCloud DNSTT Installer (Ubuntu 24.04 LTS)

Usage:
  sudo bash install.sh [ZONE] [UDP_PORT] [UPSTREAM]

Defaults:
  ZONE      $DEFAULT_ZONE
  UDP_PORT  $DEFAULT_PORT
  UPSTREAM  $DEFAULT_UPSTREAM

Example:
  sudo bash install.sh ata.jijah.loc.cc 21092 127.0.0.1:22

This installer changes only the DNSTT binary, DNSTT files and its systemd
unit. It does not change SSH settings, firewall rules, DNS records or NAT.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; exit 0; fi
[[ "$EUID" -eq 0 ]] || die "Run as root (for example: sudo bash install.sh)."

[[ -r /etc/os-release ]] || die "Cannot identify the operating system."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]] || \
  die "This installer supports Ubuntu 24.04 LTS only; detected ${PRETTY_NAME:-unknown}."

[[ "$ZONE" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?))+$ ]] || \
  die "Invalid DNS zone: $ZONE"
[[ "$DNS_PORT" =~ ^[0-9]{1,5}$ ]] || die "UDP port must be numeric."
(( 10#$DNS_PORT >= 1024 && 10#$DNS_PORT <= 65535 )) || die "Use an unprivileged UDP port from 1024 to 65535."
[[ "$UPSTREAM" =~ ^(127\.0\.0\.1|localhost|\[::1\]):[0-9]{1,5}$ ]] || \
  die "Upstream must be loopback only, for example 127.0.0.1:22."
UPSTREAM_PORT="${UPSTREAM##*:}"
(( 10#$UPSTREAM_PORT >= 1 && 10#$UPSTREAM_PORT <= 65535 )) || die "Invalid upstream TCP port."

log "Checking upstream TCP service at $UPSTREAM"
if command -v ss >/dev/null 2>&1; then
  if ! ss -lntH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:|\])${UPSTREAM_PORT}$"; then
    log "WARNING: no local TCP listener detected on port $UPSTREAM_PORT. DNSTT can start, but tunneled connections will fail until the upstream is listening."
  fi
fi

if command -v ss >/dev/null 2>&1; then
  CURRENT_UDP="$(ss -H -lunp "sport = :$DNS_PORT" 2>/dev/null || true)"
  if [[ -n "$CURRENT_UDP" ]] && ! grep -q 'dnstt-server' <<<"$CURRENT_UDP"; then
    printf '%s\n' "$CURRENT_UDP" >&2
    die "UDP port $DNS_PORT is already occupied by another process. Choose a free port."
  fi
fi

log "Installing build dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates git golang-go iproute2

TMP_DIR="$(mktemp -d /tmp/pakaicloud-dnstt-build.XXXXXX)"
log "Cloning current upstream DNSTT source"
git clone --depth 1 "$SOURCE_REPO" "$TMP_DIR/dnstt"
[[ -d "$TMP_DIR/dnstt/dnstt-server" ]] || die "Upstream source does not contain dnstt-server/."
UPSTREAM_COMMIT="$(git -C "$TMP_DIR/dnstt" rev-parse HEAD)"

log "Building dnstt-server from upstream source"
(
  cd "$TMP_DIR/dnstt/dnstt-server"
  export GOTOOLCHAIN=auto
  go build -trimpath -ldflags='-s -w' -o "$TMP_DIR/dnstt-server" .
)
[[ -x "$TMP_DIR/dnstt-server" ]] || die "DNSTT build failed."

log "Preparing dedicated service account"
if ! id dnstt >/dev/null 2>&1; then
  useradd --system --user-group --home-dir /var/lib/dnstt --create-home --shell /usr/sbin/nologin dnstt
else
  if ! getent group dnstt >/dev/null 2>&1; then
    groupadd --system dnstt
    usermod -g dnstt dnstt
  fi
fi
install -d -o root -g dnstt -m 0750 /etc/dnstt
install -d -o dnstt -g dnstt -m 0750 /var/lib/dnstt

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="/root/dnstt-installer-backup-$STAMP"
NEED_BACKUP=0
for file in "$BIN_FILE" "$SERVICE_FILE" "$ENV_FILE" "$KEY_FILE" "$PUB_FILE"; do
  [[ -e "$file" ]] && NEED_BACKUP=1
done
if (( NEED_BACKUP )); then
  install -d -m 0700 "$BACKUP_DIR"
  for file in "$BIN_FILE" "$SERVICE_FILE" "$ENV_FILE" "$KEY_FILE" "$PUB_FILE"; do
    if [[ -e "$file" ]]; then
      rel="${file#/}"
      install -d -m 0700 "$BACKUP_DIR/$(dirname "$rel")"
      cp -a "$file" "$BACKUP_DIR/$rel"
    fi
  done
  log "Existing DNSTT files backed up to $BACKUP_DIR"
fi

log "Installing DNSTT binary"
install -o root -g root -m 0755 "$TMP_DIR/dnstt-server" "$BIN_FILE"

if [[ -e "$KEY_FILE" && -e "$PUB_FILE" ]]; then
  PRIV_VALUE="$(tr -d '\r\n ' < "$KEY_FILE")"
  PUB_VALUE="$(tr -d '\r\n ' < "$PUB_FILE")"
  [[ "$PRIV_VALUE" =~ ^[[:xdigit:]]{64}$ && "$PUB_VALUE" =~ ^[[:xdigit:]]{64}$ ]] || \
    die "Existing key files are not valid 64-character hexadecimal DNSTT keys. Restore the matching keypair before continuing."
  log "Existing complete keypair found; preserving it."
elif [[ ! -e "$KEY_FILE" && ! -e "$PUB_FILE" ]]; then
  log "Generating a new persistent DNSTT keypair"
  "$BIN_FILE" -gen-key -privkey-file "$KEY_FILE" -pubkey-file "$PUB_FILE"
else
  die "Only one key file exists. Restore the matching server.key and server.pub pair; refusing to generate a mismatched keypair."
fi

chown root:dnstt "$KEY_FILE"
chmod 0640 "$KEY_FILE"
chown root:root "$PUB_FILE"
chmod 0644 "$PUB_FILE"

log "Writing environment configuration"
cat > "$ENV_FILE" <<ENV
ZONE=$ZONE
DNS_PORT=$DNS_PORT
UPSTREAM=$UPSTREAM
ENV
chown root:root "$ENV_FILE"
chmod 0600 "$ENV_FILE"

log "Writing systemd unit"
cat > "$SERVICE_FILE" <<'UNIT'
[Unit]
Description=DNSTT DNS Tunnel Server
Wants=network-online.target
After=network-online.target ssh.service

[Service]
Type=simple
User=dnstt
Group=dnstt
EnvironmentFile=/etc/dnstt/dnstt.env
ExecStart=/usr/local/bin/dnstt-server -udp :${DNS_PORT} -privkey-file /etc/dnstt/server.key ${ZONE} ${UPSTREAM}
Restart=on-failure
RestartSec=3s
LimitNOFILE=65536
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
UMask=0077

[Install]
WantedBy=multi-user.target
UNIT
chmod 0644 "$SERVICE_FILE"

log "Validating systemd unit"
systemd-analyze verify "$SERVICE_FILE"

log "Reloading systemd and starting DNSTT"
systemctl daemon-reload
systemctl enable dnstt-server >/dev/null
systemctl restart dnstt-server
sleep 1
if ! systemctl is-active --quiet dnstt-server; then
  systemctl --no-pager --full status dnstt-server || true
  journalctl -u dnstt-server -n 40 --no-pager || true
  die "DNSTT service failed to start. Review the output above."
fi

LISTENER="$(ss -H -lunp "sport = :$DNS_PORT" 2>/dev/null || true)"
if ! grep -q 'dnstt-server' <<<"$LISTENER"; then
  log "WARNING: systemd is active but ss did not confirm the expected UDP listener. Inspect journalctl."
fi

install -d -o root -g root -m 0755 "$(dirname "$BUILD_INFO")"
cat > "$BUILD_INFO" <<BUILD
Installer: pakaicloud-dnstt-installer
Installer defaults: $DEFAULT_ZONE / UDP $DEFAULT_PORT
DNSTT upstream repository: $SOURCE_REPO
DNSTT upstream commit: $UPSTREAM_COMMIT
Build date: $(date -Is)
Ubuntu: ${PRETTY_NAME:-Ubuntu 24.04}
BUILD
chmod 0644 "$BUILD_INFO"

PUBKEY="$(tr -d '\r\n ' < "$PUB_FILE")"
cat > "$INFO_FILE" <<INFO
PAKAICLOUD DNSTT CLIENT INFO
============================
Zone: $ZONE
Direct UDP endpoint: PUBLIC_IP:$DNS_PORT
Server public key: $PUBKEY
SSH upstream: $UPSTREAM

HTTP Custom / compatible client (when custom UDP endpoint is supported):
DNS endpoint: udp://PUBLIC_IP:$DNS_PORT
NS / tunnel zone: $ZONE
Public key: $PUBKEY

IMPORTANT:
- Keep /etc/dnstt/server.key private. Never upload or share it.
- Copy only server.pub / the public key to clients.
- Replace PUBLIC_IP with the public gateway address.
- NAT must forward public UDP $DNS_PORT to this VPS UDP $DNS_PORT.
- For standard recursive DNS delegation, DNS queries normally arrive on public UDP 53;
  a custom UDP port requires a client that explicitly supports it.
- SSH configuration, passwords, firewall and provider NAT were not changed.
INFO
chmod 0600 "$INFO_FILE"

log "Installation completed"
printf '\n%s\n' '================ DNSTT INSTALL SUMMARY ================'
printf 'Zone             : %s\n' "$ZONE"
printf 'UDP listen       : :%s\n' "$DNS_PORT"
printf 'TCP upstream     : %s\n' "$UPSTREAM"
printf 'Service          : %s\n' "$(systemctl is-active dnstt-server)"
printf 'Private key      : %s (keep secret)\n' "$KEY_FILE"
printf 'Public key       : %s\n' "$PUB_FILE"
printf 'Client info      : %s\n' "$INFO_FILE"
printf 'Upstream commit  : %s\n' "$UPSTREAM_COMMIT"
printf '\nPublic key for client:\n%s\n' "$PUBKEY"
printf '\nUseful checks:\n'
printf '  systemctl status dnstt-server --no-pager\n'
printf '  journalctl -u dnstt-server -n 30 --no-pager\n'
printf '  ss -lunp | grep ":%s"\n' "$DNS_PORT"
printf '\nSSH settings, firewall rules and NAT mappings were not modified.\n'
