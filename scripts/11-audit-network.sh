#!/usr/bin/env bash
# shellcheck shell=bash
set -Eeuo pipefail

# Описание: Скрипт аудита сетевой конфигурации Proxmox.
# Проверяет состояние физических интерфейсов, мостов, маршрутизации,
# DNS, IP forwarding, бэкенд iptables/nftables, NAT, dnsmasq, firewall и VM.
# Использование: sudo bash scripts/11-audit-network.sh

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

OK="${GREEN}[OK]${NC}"
WARN="${YELLOW}[WARN]${NC}"
FAIL="${RED}[FAIL]${NC}"
INFO="${BLUE}[INFO]${NC}"

print_header() {
    echo
    echo "======================================================"
    echo " PROXMOX NETWORK AUDIT"
    echo "======================================================"
    echo
}

print_section() {
    local title="$1"
    echo "------------------------------------------------------"
    echo "$title"
    echo "------------------------------------------------------"
}

print_header

# ------------------------------------------------------------
# Определяем внешний мост по default-роуту
# ------------------------------------------------------------
WAN_BRIDGE=$(ip route | awk '/default/ {print $5; exit}')

if [[ -z "${WAN_BRIDGE}" ]]; then
    echo -e "${FAIL} Не удалось определить WAN bridge"
    exit 1
fi

echo -e "${INFO} WAN bridge detected: ${WAN_BRIDGE}"

# ------------------------------------------------------------
# Определяем внутренний мост по адресу 10.x.x.x
# ------------------------------------------------------------
INTERNAL_BRIDGE=$(ip -o -4 addr show | awk '$4 ~ /^10\./ {print $2; exit}')

if [[ -z "${INTERNAL_BRIDGE}" ]]; then
    INTERNAL_BRIDGE="vmbr1"
fi

echo -e "${INFO} Internal bridge detected: ${INTERNAL_BRIDGE}"

echo

# ------------------------------------------------------------
# 1. Проверка физических NIC
# ------------------------------------------------------------
print_section "1. PHYSICAL NIC"
ip link show

echo
if ip link show | grep -q LOWER_UP; then
    echo -e "${OK} Physical NIC link is UP"
else
    echo -e "${FAIL} Physical NIC link DOWN"
fi

echo
printf 'NIC statistics:\n'
ip -s link

echo

# ------------------------------------------------------------
# 2. Проверка мостов
# ------------------------------------------------------------
print_section "2. BRIDGES"

if command -v brctl >/dev/null 2>&1; then
    brctl show
elif command -v bridge >/dev/null 2>&1; then
    bridge link
else
    echo -e "${WARN} Не найден brctl или bridge"
fi

echo
if command -v bridge >/dev/null 2>&1; then
    bridge link
else
    echo -e "${WARN} Команда bridge отсутствует"
fi

echo
if command -v bridge >/dev/null 2>&1 && bridge link | grep -q "master ${WAN_BRIDGE}"; then
    echo -e "${OK} Physical NIC attached to ${WAN_BRIDGE}"
else
    echo -e "${WARN} Не удалось подтвердить участие NIC в мосту"
fi

echo

# ------------------------------------------------------------
# 3. Проверка IP-адресов
# ------------------------------------------------------------
print_section "3. IP ADDRESSES"
ip a

echo

# ------------------------------------------------------------
# 4. Проверка маршрутизации
# ------------------------------------------------------------
print_section "4. ROUTING"
ip r

echo
if ip route | grep -q '^default'; then
    echo -e "${OK} Default route exists"
else
    echo -e "${FAIL} Default route missing"
fi

echo

# ------------------------------------------------------------
# 5. Проверка доступа в интернет
# ------------------------------------------------------------
print_section "5. INTERNET CONNECTIVITY"

if ping -c 2 1.1.1.1 >/dev/null 2>&1; then
    echo -e "${OK} ICMP internet connectivity OK"
else
    echo -e "${FAIL} Cannot reach internet IP"
fi

if ping -c 2 google.com >/dev/null 2>&1; then
    echo -e "${OK} DNS resolution OK"
else
    echo -e "${FAIL} DNS resolution failed"
fi

echo
printf '/etc/resolv.conf:\n'
cat /etc/resolv.conf

echo

# ------------------------------------------------------------
# 6. Проверка IP forwarding
# ------------------------------------------------------------
print_section "6. IP FORWARDING"

sysctl net.ipv4.ip_forward

echo
if [[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]]; then
    echo -e "${OK} IPv4 forwarding enabled"
else
    echo -e "${FAIL} IPv4 forwarding disabled"
fi

echo

# ------------------------------------------------------------
# 7. Проверка backend iptables/nftables
# ------------------------------------------------------------
print_section "7. IPTABLES / NFT BACKEND"

update-alternatives --display iptables || true

echo
CURRENT_BACKEND=$(update-alternatives --display iptables 2>/dev/null | grep 'link currently points to' || true)
echo "${CURRENT_BACKEND}"

echo
if echo "${CURRENT_BACKEND}" | grep -q 'iptables-nft'; then
    echo -e "${OK} iptables-nft backend active"
else
    echo -e "${WARN} iptables-legacy backend active"
    echo -e "${WARN} Recommended command:"
    echo "update-alternatives --set iptables /usr/sbin/iptables-nft"
fi

echo

# ------------------------------------------------------------
# 8. Проверка nftables
# ------------------------------------------------------------
print_section "8. NFTABLES"

if systemctl is-active nftables >/dev/null 2>&1; then
    echo -e "${OK} nftables service active"
else
    echo -e "${WARN} nftables service inactive"
fi

echo
nft list ruleset 2>/dev/null || true

echo
if nft list ruleset 2>/dev/null | grep -qi masquerade; then
    echo -e "${OK} NAT masquerade rule found"
else
    echo -e "${WARN} NAT masquerade not found in nftables"
fi

echo

# ------------------------------------------------------------
# 9. Проверка iptables правил
# ------------------------------------------------------------
print_section "9. IPTABLES RULES"

iptables -L -n -v 2>/dev/null || true

echo
iptables -t nat -L -n -v 2>/dev/null || true

echo
if iptables -t nat -L 2>/dev/null | grep -q MASQUERADE; then
    echo -e "${OK} MASQUERADE rule exists"
else
    echo -e "${WARN} MASQUERADE rule missing"
fi

echo
if iptables -L FORWARD 2>/dev/null | grep -q ACCEPT; then
    echo -e "${OK} FORWARD rules detected"
else
    echo -e "${WARN} FORWARD rules missing"
fi

echo

# ------------------------------------------------------------
# 10. Проверка dnsmasq
# ------------------------------------------------------------
print_section "10. DNSMASQ"

if systemctl is-active dnsmasq >/dev/null 2>&1; then
    echo -e "${OK} dnsmasq running"
else
    echo -e "${WARN} dnsmasq not running"
fi

echo
systemctl --no-pager --full status dnsmasq || true

echo
printf 'dnsmasq leases:\n'
cat /var/lib/misc/dnsmasq.leases 2>/dev/null || true

echo

# ------------------------------------------------------------
# 11. Проверка Proxmox firewall
# ------------------------------------------------------------
print_section "11. PROXMOX FIREWALL"
pve-firewall status || true
echo

# ------------------------------------------------------------
# 12. Проверка fstrim.timer
# ------------------------------------------------------------
print_section "12. FSTRIM"
systemctl status fstrim.timer --no-pager || true
echo

# ------------------------------------------------------------
# 13. Проверка сетевых конфигураций VM
# ------------------------------------------------------------
print_section "13. VM NETWORK CONFIGS"

qm list | awk 'NR>1 {print $1}' | while read -r VMID; do
    echo
    echo "VMID: ${VMID}"
    qm config "${VMID}" | grep -E 'net0|agent|ipconfig' || true
    echo
 done

echo

# ------------------------------------------------------------
# 14. Рекомендации
# ------------------------------------------------------------
print_section "14. RECOMMENDATIONS"

echo
if ! echo "${CURRENT_BACKEND}" | grep -q 'iptables-nft'; then
    echo -e "${WARN} Switch to nft backend:"
    echo "update-alternatives --set iptables /usr/sbin/iptables-nft"
    echo
fi

if ! iptables -L FORWARD 2>/dev/null | grep -q ACCEPT; then
    echo -e "${WARN} Add FORWARD rules:"
    echo "iptables -A FORWARD -i ${INTERNAL_BRIDGE} -o ${WAN_BRIDGE} -j ACCEPT"
    echo "iptables -A FORWARD -i ${WAN_BRIDGE} -o ${INTERNAL_BRIDGE} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT"
    echo
fi

if ! iptables -t nat -L 2>/dev/null | grep -q MASQUERADE; then
    echo -e "${WARN} Add NAT rule:"
    echo "iptables -t nat -A POSTROUTING -s 10.10.10.0/24 -o ${WAN_BRIDGE} -j MASQUERADE"
    echo
fi

echo -e "${INFO} Audit complete"
echo
