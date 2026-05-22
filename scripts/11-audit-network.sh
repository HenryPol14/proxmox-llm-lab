#!/usr/bin/env bash
set -Eeuo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

OK="${GREEN}[OK]${NC}"
WARN="${YELLOW}[WARN]${NC}"
FAIL="${RED}[FAIL]${NC}"
INFO="${BLUE}[INFO]${NC}"

echo "======================================================"
echo " PROXMOX VE NETWORK AUDIT (READ ONLY)"
echo "======================================================"

echo "-- System info --"
hostnamectl || true
uname -a
pveversion || true

WAN_BRIDGE=$(ip route | awk '/default/ {print $5}' | head -n1)
if [[ -z "$WAN_BRIDGE" ]]; then
  echo -e "${FAIL} Не удалось определить WAN bridge"
  exit 1
fi

echo -e "${INFO} WAN bridge: ${WAN_BRIDGE}"

INTERNAL_BRIDGE=$(ip -o -4 addr show | awk '$4 ~ /^10\./ {print $2}' | head -n1)
INTERNAL_BRIDGE=${INTERNAL_BRIDGE:-vmbr1}
echo -e "${INFO} Internal bridge: ${INTERNAL_BRIDGE}"

echo "-- SSH safety --"
who || true
SSH_PORT=$(ss -tlnp 2>/dev/null | awk '/sshd/ {print $4}' | sed 's/.*://' | head -n1)
SSH_PORT=${SSH_PORT:-22}
echo -e "${INFO} SSH port: ${SSH_PORT}"
if nft list ruleset 2>/dev/null | grep -q "dport ${SSH_PORT}"; then
  echo -e "${OK} SSH rule found in nftables"
else
  echo -e "${WARN} SSH rule not found in nftables"
fi

echo "-- Firewall services --"
systemctl --no-pager --type=service | grep firewal || true
systemctl is-active proxmox-firewall >/dev/null 2>&1 && echo -e "${OK} proxmox-firewall active" || echo -e "${WARN} proxmox-firewall inactive"
systemctl is-active pve-firewall >/dev/null 2>&1 && echo -e "${OK} pve-firewall active" || echo -e "${WARN} pve-firewall inactive"

echo "-- Interfaces --"
ip link show
ip -s link

if command -v brctl >/dev/null 2>&1; then
  brctl show
else
  bridge link
fi

if bridge link | grep -q "master ${WAN_BRIDGE}"; then
  echo -e "${OK} Bridge membership is correct"
else
  echo -e "${WARN} Unable to confirm bridge membership"
fi

echo "-- IP addresses / routing --"
ip a
ip r
ip route | grep -q '^default' && echo -e "${OK} Default route present" || echo -e "${FAIL} Default route missing"

echo "-- Connectivity --"
if ping -c 2 1.1.1.1 >/dev/null 2>&1; then
  echo -e "${OK} Internet reachability works"
else
  echo -e "${FAIL} Internet reachability failed"
fi
if ping -c 2 google.com >/dev/null 2>&1; then
  echo -e "${OK} DNS resolution works"
else
  echo -e "${FAIL} DNS resolution failed"
fi
cat /etc/resolv.conf

echo "-- Forwarding --"
sysctl net.ipv4.ip_forward
if [[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]]; then
  echo -e "${OK} IPv4 forwarding is enabled"
else
  echo -e "${FAIL} IPv4 forwarding is disabled"
fi

echo "-- iptables backend --"
update-alternatives --display iptables || true
CURRENT_BACKEND=$(update-alternatives --display iptables 2>/dev/null | grep "link currently points to" || true)
echo "$CURRENT_BACKEND"
if echo "$CURRENT_BACKEND" | grep -q "iptables-nft"; then
  echo -e "${OK} iptables-nft backend is in use"
else
  echo -e "${WARN} legacy iptables backend is in use"
fi

echo "-- nftables --"
if systemctl is-active nftables >/dev/null 2>&1; then
  echo -e "${OK} nftables.service active"
else
  echo -e "${WARN} nftables.service inactive"
fi
nft list ruleset || true
if nft list ruleset 2>/dev/null | grep -qi masquerade; then
  echo -e "${OK} NAT masquerade found"
else
  echo -e "${WARN} NAT masquerade not found"
fi

echo "-- iptables compatibility --"
iptables -L -n -v || true
iptables -t nat -L -n -v || true
if iptables -t nat -L | grep -q MASQUERADE; then
  echo -e "${OK} MASQUERADE present"
else
  echo -e "${WARN} MASQUERADE missing"
fi

echo "-- dnsmasq --"
systemctl is-active dnsmasq >/dev/null 2>&1 && echo -e "${OK} dnsmasq active" || echo -e "${WARN} dnsmasq inactive"
systemctl --no-pager --full status dnsmasq || true
cat /var/lib/misc/dnsmasq.leases 2>/dev/null || true

echo "-- pve-firewall --"
systemctl --no-pager --full status proxmox-firewall || true
systemctl --no-pager --full status pve-firewall || true
pve-firewall status || true

echo "-- fstrim --"
systemctl status fstrim.timer --no-pager || true

echo "-- VM network configs --"
for VMID in $(qm list | awk 'NR>1 {print $1}'); do
  echo "VMID: ${VMID}"
  qm config "${VMID}" | grep -E 'net0|agent|ipconfig' || true
  echo
 done

echo "-- recommendations --"
if ! echo "$CURRENT_BACKEND" | grep -q "iptables-nft"; then
  echo -e "${WARN} Recommended: switch to nft backend"
  echo "update-alternatives --set iptables /usr/sbin/iptables-nft"
fi
if ! nft list ruleset 2>/dev/null | grep -qi masquerade; then
  echo -e "${WARN} NAT masquerade is missing"
  echo "Check NAT/firewall configuration."
fi
if [[ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]]; then
  echo -e "${WARN} IPv4 forwarding is disabled"
  echo "sysctl -w net.ipv4.ip_forward=1"
fi

echo -e "${INFO} Audit complete"
