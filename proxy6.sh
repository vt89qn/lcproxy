#!/bin/bash
# proxy6.sh - tạo proxy HTTP IPv6 (3proxy) trên interface ứng với một gateway IPv4
#
#   proxy6.sh -port 20000 -count 100                      # interface ra Internet chính
#   proxy6.sh -gw 192.168.1.1   -port 20000 -count 100
#   proxy6.sh -gw 192.168.201.1 -port 20200 -count 100 -prefix '2402:9d80:3a0:666'
#
# Không truyền -gw: dùng interface có default route metric thấp nhất (ưu tiên
# route IPv6, không có thì route IPv4), bỏ qua tailscale0.
#
# Mỗi port (port .. port+count-1) đi ra Internet bằng một IPv6 ngẫu nhiên riêng
# trong prefix /64. IPv6 chỉ sống 10 phút. Proxy chỉ nghe trên IP Tailscale.
# In ra 'start_proxy_ok' khi mọi thứ chạy ổn.

set -euo pipefail
export PATH=$PATH:/usr/sbin:/sbin

LIFETIME=600                 # giây, IPv6 tự hết hạn sau 10 phút
CONF_DIR=/etc/3proxy
RUN_DIR=/run/3proxy

die() { echo "ERROR: $*" >&2; exit 1; }

# ---------- tham số ----------
GW= PORT= COUNT= PREFIX=
while [ $# -gt 0 ]; do
  case "$1" in
    -gw)     GW=$2;     shift 2 ;;
    -port)   PORT=$2;   shift 2 ;;
    -count)  COUNT=$2;  shift 2 ;;
    -prefix) PREFIX=$2; shift 2 ;;
    *) die "tham số không hợp lệ: $1" ;;
  esac
done
[ -n "$PORT" ] && [ -n "$COUNT" ] || die "cần -port, -count"
[ "$(id -u)" = 0 ] || die "phải chạy bằng root"
LAST_PORT=$((PORT + COUNT - 1))

# ---------- 1. tìm interface ----------
# In "metric dev" của từng default route (cả route multipath), metric thiếu thì coi là 1024
default_devs() {
  ip -o "$1" route show default | awk '{
    m = 1024
    for (i = 1; i < NF; i++) if ($i == "metric") m = $(i + 1)
    for (i = 1; i < NF; i++) if ($i == "dev" && $(i + 1) != "tailscale0") print m, $(i + 1)
  }'
}
if [ -n "$GW" ]; then
  IFACE=$(ip -4 route get "$GW" | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -1)
  [ -n "$IFACE" ] || die "không tìm thấy interface cho gateway $GW"
else
  IFACE=$( { default_devs -6; } | sort -n | awk 'NR == 1 {print $2}')
  [ -n "$IFACE" ] || IFACE=$( { default_devs -4; } | sort -n | awk 'NR == 1 {print $2}')
  [ -n "$IFACE" ] || die "không tìm thấy interface ra Internet"
fi

# ---------- 2. prefix /64 ----------
if [ -z "$PREFIX" ]; then
  # IPv6 chính do modem/router cấp qua RA: global, dynamic (RA), không phải
  # địa chỉ tạm (random), không deprecated/tentative, prefix /64.
  # VPS thường đặt IPv6 tĩnh (không có RA): khi đó lấy IPv6 global /64 tĩnh.
  CANDIDATES=$(ip -6 -o addr show dev "$IFACE" scope global -temporary -deprecated -tentative -dadfailed)
  ADDR=$(echo "$CANDIDATES" | awk '$4 ~ /\/64$/ && /dynamic/ {print $4; exit}')
  [ -n "$ADDR" ] || ADDR=$(echo "$CANDIDATES" | awk '$4 ~ /\/64$/ {print $4; exit}')
  [ -n "$ADDR" ] || die "không tìm thấy IPv6 /64 trên $IFACE"
  PREFIX=$(python3 -c 'import ipaddress,sys; a=ipaddress.IPv6Interface(sys.argv[1]).ip.exploded; print(":".join(a.split(":")[:4]))' "$ADDR")
fi
# chuẩn hoá 4 phần đầu, bỏ số 0 thừa: 2402:0800:... -> 2402:800:...
PREFIX=$(python3 -c 'import ipaddress,sys; n=ipaddress.IPv6Network(sys.argv[1].rstrip(":")+"::/64"); print(":".join(format(int(x,16),"x") for x in n.network_address.exploded.split(":")[:4]))' "$PREFIX" 2>/dev/null) \
  || die "prefix không hợp lệ"

# ---------- 3. IP Tailscale để proxy nghe ----------
TS_IP=$(tailscale ip -4 2>/dev/null | head -1)
[ -n "$TS_IP" ] || die "không lấy được IP Tailscale"
# tên máy trong tailnet (phần đầu của MagicDNS name), ví dụ "debian"
TS_NAME=$(tailscale status --json 2>/dev/null \
          | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].split(".")[0])' 2>/dev/null || true)
[ -n "$TS_NAME" ] || TS_NAME=$(hostname)

# ---------- 4. interface phải có default route IPv6 ----------
# Không cần rule định tuyến: mỗi proxy dùng -De<iface> (gắn socket ra vào đúng
# interface), kernel tự chọn default route IPv6 của interface đó.
ip -6 route show default | grep -q " dev $IFACE " || die "$IFACE chưa có default route IPv6"

# ---------- 5. cài 3proxy bản mới nhất nếu chưa có ----------
if ! command -v 3proxy >/dev/null; then
  case "$(uname -m)" in
    aarch64) ARCH=arm64 ;;
    x86_64)  ARCH=x86_64 ;;
    armv7l)  ARCH=arm ;;
    *) die "kiến trúc $(uname -m) chưa hỗ trợ" ;;
  esac
  TMP=$(mktemp -d)
  TAG=$(curl -fsSL https://api.github.com/repos/3proxy/3proxy/releases/latest \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
  BASE=https://github.com/3proxy/3proxy/releases/download/$TAG
  DEB=3proxy-$TAG.$ARCH.deb
  curl -fsSL -o "$TMP/$DEB" "$BASE/$DEB"
  curl -fsSL -o "$TMP/SUMS" "$BASE/SHA256SUMS-$ARCH"
  (cd "$TMP" && grep " $DEB\$" SUMS | sha256sum -c -) >/dev/null || die "sai checksum $DEB"
  dpkg -i "$TMP/$DEB" >/dev/null
  rm -rf "$TMP"
  # gói .deb tự bật service mặc định, tắt đi vì mình tự chạy theo config riêng
  systemctl disable --now 3proxy >/dev/null 2>&1 || true
  command -v 3proxy >/dev/null || die "cài 3proxy thất bại"
fi
BIN=$(command -v 3proxy)

# ---------- 6. dừng 3proxy cũ đang chiếm port đầu tiên ----------
OLD_PID=$(ss -ltnpH "sport = :$PORT" | grep -o '"3proxy",pid=[0-9]*' | grep -o '[0-9]*$' | head -1 || true)
if [ -n "$OLD_PID" ]; then
  kill "$OLD_PID"
  for _ in $(seq 1 20); do kill -0 "$OLD_PID" 2>/dev/null || break; sleep 0.25; done
  kill -9 "$OLD_PID" 2>/dev/null || true
fi

# ---------- 7. thêm IPv6 ngẫu nhiên + viết config ----------
mkdir -p "$CONF_DIR" "$RUN_DIR"
CFG=$CONF_DIR/p6-$PORT.cfg
{
  echo "daemon"
  echo "pidfile $RUN_DIR/p6-$PORT.pid"
  echo "nserver 127.0.2.1"   # dnscrypt-proxy: DNS của Cloudflare qua HTTPS, tránh bị chặn DNS
  echo "nscache6 65536"
  echo "maxconn 5000"
  echo "timeouts 1 5 30 60 180 1800 15 60"
  echo "auth none"
} > "$CFG"

for i in $(seq 0 $((COUNT - 1))); do
  SUFFIX=$(od -An -N8 -tx2 /dev/urandom | awk '{print $1":"$2":"$3":"$4}')
  IP6=$PREFIX:$SUFFIX
  ip -6 addr add "$IP6/128" dev "$IFACE" nodad valid_lft $LIFETIME preferred_lft $LIFETIME
  echo "proxy -6 -n -a -p$((PORT + i)) -i$TS_IP -e$IP6 -De$IFACE" >> "$CFG"
done

# ---------- 8. chạy 3proxy ----------
ulimit -n 65535
"$BIN" "$CFG" </dev/null >/dev/null 2>&1   # không giữ stdout, để lệnh gọi script không bị treo

# ---------- 9. kiểm tra ----------
for _ in $(seq 1 20); do
  ss -ltnH "sport = :$LAST_PORT" | grep -q . && break; sleep 0.25
done
ss -ltnH "sport = :$PORT"      | grep -q . || die "3proxy không nghe trên port $PORT"
ss -ltnH "sport = :$LAST_PORT" | grep -q . || die "3proxy không nghe trên port $LAST_PORT"

echo "start_proxy_ok iface=$IFACE prefix=$PREFIX::/64 ports=$PORT-$LAST_PORT listen=$TS_IP ts-name=$TS_NAME"
