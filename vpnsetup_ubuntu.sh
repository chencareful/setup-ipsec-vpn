#!/bin/bash
# L2TP/IPsec VPN Auto Installer with 5 fixed users and fixed PSK

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# User config
VPN_USERS=("vip1" "vip2" "vip3" "vip4" "vip5")
VPN_PASSWORD="258258"
VPN_IPSEC_PSK="Q7hFj3XpLmZr982TkAVc"  # <-- 固定预设 PSK

bigecho() {
  echo -e "\\n\033[1m$1\033[0m\n"
}

exiterr() {
  echo "Error: $1" >&2
  exit 1
}

conf_bk() {
  [ -f "$1" ] && cp -f "$1" "$1.old-$(date +%Y%m%d%H%M%S)"
}

install_packages() {
  bigecho "Installing required packages..."

  export DEBIAN_FRONTEND=noninteractive
  apt-get -yq update
  apt-get -yqq install libnss3-dev libnspr4-dev pkg-config libpam0g-dev \
    libcap-ng-dev libcap-ng-utils libselinux-dev libcurl4-nss-dev flex bison \
    gcc make libunbound-dev libnss3-tools libevent-dev xmlto libsystemd-dev \
    libkrb5-dev git curl xl2tpd ppp iptables iproute2 gawk openssl

  if ! command -v ipsec >/dev/null 2>&1; then
    bigecho "Installing Libreswan (IPsec VPN software)..."
    cd /opt || exit 1
    LIBRESWAN_VER=4.15
    wget -t 3 -T 30 -nv -O libreswan-${LIBRESWAN_VER}.tar.gz \
      "https://github.com/libreswan/libreswan/archive/v${LIBRESWAN_VER}.tar.gz"
    tar xzf libreswan-${LIBRESWAN_VER}.tar.gz && cd libreswan-${LIBRESWAN_VER}
    make -s programs && make -s install
  fi
}

create_vpn_config() {
  bigecho "Creating VPN configuration..."

  mkdir -p /etc/ipsec.d

  cat > /etc/ipsec.conf <<EOF
config setup
  uniqueids=no

conn %default
  keyexchange=ikev1
  authby=secret
  ike=aes256-sha2_256;modp2048
  esp=aes256-sha2_256
  dpdaction=clear
  dpddelay=300s
  rekey=no

conn L2TP-PSK
  keyexchange=ikev1
  auto=add
  left=%defaultroute
  leftid=$(curl -s https://ipinfo.io/ip)
  leftfirewall=yes
  leftprotoport=17/1701
  right=%any
  rightprotoport=17/%any
  type=transport
  authby=secret
  pfs=no
  ikev2=never
EOF

  cat > /etc/ipsec.secrets <<EOF
%any  %any  : PSK "$VPN_IPSEC_PSK"
EOF

  cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
port = 1701

[lns default]
ip range = 192.168.42.10-192.168.42.250
local ip = 192.168.42.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

  cat > /etc/ppp/options.xl2tpd <<EOF
require-mschap-v2
refuse-chap
refuse-pap
ms-dns 8.8.8.8
ms-dns 1.1.1.1
asyncmap 0
auth
crtscts
lock
hide-password
modem
debug
name l2tpd
proxyarp
lcp-echo-interval 30
lcp-echo-failure 4
mtu 1410
mru 1410
connect-delay 5000
EOF

  conf_bk "/etc/ppp/chap-secrets"
  conf_bk "/etc/ipsec.d/passwd"
  : > /etc/ppp/chap-secrets
  : > /etc/ipsec.d/passwd

  for user in "${VPN_USERS[@]}"; do
    echo "\"$user\" l2tpd \"$VPN_PASSWORD\" *" >> /etc/ppp/chap-secrets
    pass_enc=$(openssl passwd -1 "$VPN_PASSWORD")
    echo "$user:$pass_enc:xauth-psk" >> /etc/ipsec.d/passwd
  done
}

enable_services() {
  bigecho "Enabling VPN services..."
  systemctl enable ipsec
  systemctl enable xl2tpd
  systemctl restart ipsec
  systemctl restart xl2tpd
}

show_vpn_info() {
  public_ip=$(curl -s https://ipinfo.io/ip)
  cat <<EOF

================================================

IPsec VPN server is now ready for use!

Server IP : $public_ip
IPsec PSK : $VPN_IPSEC_PSK

VPN Users (Password: $VPN_PASSWORD):
EOF

  for user in "${VPN_USERS[@]}"; do
    echo "  - $user"
  done

  echo ""
  echo "VPN client setup guide: https://vpnsetup.net/clients"
  echo ""
  echo "================================================"
}

### Run the installer

bigecho "Welcome! Setting up your L2TP/IPSec VPN server..."
install_packages
create_vpn_config
enable_services
show_vpn_info
