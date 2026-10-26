#!/bin/bash
# setup-doh.sh - cài dnscrypt-proxy làm DNS cục bộ (Cloudflare qua HTTPS) cho 3proxy
#
# Sau khi chạy: DNS cục bộ nghe ở 127.0.2.1:53 (UDP/TCP)
# proxy6.sh dùng "nserver 127.0.2.1".
#

set -euo pipefail
export PATH=$PATH:/usr/sbin:/sbin DEBIAN_FRONTEND=noninteractive

die() { echo "ERROR: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "phải chạy bằng root"
CONF=/etc/dnscrypt-proxy/dnscrypt-proxy.toml

# ---------- 1. cài gói ----------
if ! dpkg -s dnscrypt-proxy >/dev/null 2>&1; then
  apt-get update -q
  apt-get install -y -q dnscrypt-proxy
fi

# ---------- 2. cấu hình: chỉ dùng Cloudflare DoH (IPv4 + IPv6) ----------
cp -n "$CONF" "$CONF.orig"          # giữ bản gốc một lần
set_opt() {  # set_opt key value  (sửa nếu có, thêm lên đầu file nếu chưa có)
  if grep -q "^$1 = " "$CONF"; then
    sed -i "s|^$1 = .*|$1 = $2|" "$CONF"
  else
    sed -i "1i $1 = $2" "$CONF"
  fi
}
set_opt server_names "['cloudflare', 'cloudflare-ipv6']"
set_opt doh_servers true
set_opt ipv6_servers true
# Gói Debian dùng systemd socket (127.0.2.1:53), nên listen_addresses phải để trống
set_opt listen_addresses "[]"

# ---------- 3. không để dnscrypt-proxy sửa resolv.conf (Tailscale quản lý) ----------
systemctl disable --now dnscrypt-proxy-resolvconf.service >/dev/null 2>&1 || true

# ---------- 4. chạy ----------
systemctl enable dnscrypt-proxy.socket dnscrypt-proxy.service >/dev/null 2>&1
systemctl restart dnscrypt-proxy.socket dnscrypt-proxy.service
for _ in $(seq 1 20); do
  journalctl -u dnscrypt-proxy --since "-1 min" --no-pager 2>/dev/null | grep -q "is ready" && break
  sleep 0.5
done

echo 'doh_ok'
