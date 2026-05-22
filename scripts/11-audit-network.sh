#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# PROXMOX NETWORK AUDIT (READ ONLY)
# ============================================================
#
# Безопасный аудит сетевой подсистемы Proxmox VE 9+
#
# СОВМЕСТИМО:
#   - Proxmox VE 9
#   - nftables firewall
#   - pve-firewall
#   - kernel 7.x pve
#
# БЕЗОПАСНО ДЛЯ SSH:
#   Скрипт НЕ изменяет:
#     - nftables
#     - iptables
#     - routing
#     - bridges
#     - networking
#
# Скрипт только ЧИТАЕТ состояние системы.
#
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

OK="${GREEN}[OK]${NC}"
WARN="${YELLOW}[WARN]${NC}"
FAIL="${RED}[FAIL]${NC}"
INFO="${BLUE}[INFO]${NC}"

echo
echo "======================================================"
echo " PROXMOX VE NETWORK AUDIT (READ ONLY)"
echo " SAFE FOR REMOTE SSH EXECUTION"
echo " NFTABLES / PVE-FIREWALL AWARE"
echo "======================================================"
echo

# ------------------------------------------------------------
# SYSTEM INFO
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " SYSTEM INFO"
echo "------------------------------------------------------"

echo
hostnamectl || true

echo
echo "Kernel:"
uname -a

echo
echo "Proxmox version:"
pveversion || true

echo

# ------------------------------------------------------------
# DETECT WAN BRIDGE
# ------------------------------------------------------------

WAN_BRIDGE=$(ip route | awk '/default/ {print $5}' | head -n1)

if [[ -z "${WAN_BRIDGE}" ]]; then
    echo -e "${FAIL} Не удалось определить WAN bridge"
    exit 1
fi

echo -e "${INFO} WAN bridge: ${WAN_BRIDGE}"

# ------------------------------------------------------------
# DETECT INTERNAL BRIDGE
# ------------------------------------------------------------

INTERNAL_BRIDGE=$(ip -o -4 addr show | awk '$4 ~ /^10\./ {print $2}' | head -n1)

if [[ -z "${INTERNAL_BRIDGE}" ]]; then
    INTERNAL_BRIDGE="vmbr1"
fi

echo -e "${INFO} Internal bridge: ${INTERNAL_BRIDGE}"

echo

# ------------------------------------------------------------
# SSH SAFETY CHECK
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " SSH SAFETY CHECK"
echo "------------------------------------------------------"

echo
echo "Активные SSH сессии:"
echo

who || true

echo

SSH_PORT=$(ss -tlnp 2>/dev/null | awk '/sshd/ {print $4}' | sed 's/.*://' | head -n1)
SSH_PORT=${SSH_PORT:-22}

echo -e "${INFO} SSH порт: ${SSH_PORT}"

echo

# Проверяем SSH rules через nftables
if nft list ruleset 2>/dev/null | grep -q "dport ${SSH_PORT}"; then
    echo -e "${OK} SSH правило найдено в nftables"
else
    echo -e "${WARN} SSH правило явно не найдено"
fi

echo

# ------------------------------------------------------------
# FIREWALL SERVICES
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " FIREWALL SERVICES"
echo "------------------------------------------------------"

systemctl --no-pager --type=service | grep firewal || true

echo

# Проверяем proxmox-firewall
if systemctl is-active proxmox-firewall >/dev/null 2>&1; then
    echo -e "${OK} proxmox-firewall active"
else
    echo -e "${WARN} proxmox-firewall inactive"
fi

# Проверяем pve-firewall
if systemctl is-active pve-firewall >/dev/null 2>&1; then
    echo -e "${OK} pve-firewall active"
else
    echo -e "${WARN} pve-firewall inactive"
fi

echo

# ------------------------------------------------------------
# PHYSICAL NIC CHECK
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " PHYSICAL INTERFACES"
echo "------------------------------------------------------"

ip link show

echo

if ip link show | grep -q LOWER_UP; then
    echo -e "${OK} Есть интерфейсы в состоянии LOWER_UP"
else
    echo -e "${FAIL} LOWER_UP интерфейсы отсутствуют"
fi

echo

echo "Статистика интерфейсов:"
echo

ip -s link

echo

# ------------------------------------------------------------
# BRIDGES
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " BRIDGES"
echo "------------------------------------------------------"

if command -v brctl >/dev/null 2>&1; then
    brctl show
else
    bridge link
fi

echo

bridge link

echo

if bridge link | grep -q "master ${WAN_BRIDGE}"; then
    echo -e "${OK} Bridge membership корректен"
else
    echo -e "${WARN} Не удалось подтвердить bridge membership"
fi

echo

# ------------------------------------------------------------
# IP ADDRESSES
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " IP ADDRESSES"
echo "------------------------------------------------------"

ip a

echo

# ------------------------------------------------------------
# ROUTING
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " ROUTING"
echo "------------------------------------------------------"

ip r

echo

if ip route | grep -q "^default"; then
    echo -e "${OK} Default route присутствует"
else
    echo -e "${FAIL} Default route отсутствует"
fi

echo

# ------------------------------------------------------------
# CONNECTIVITY
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " INTERNET CONNECTIVITY"
echo "------------------------------------------------------"

if ping -c 2 1.1.1.1 >/dev/null 2>&1; then
    echo -e "${OK} Интернет по IP доступен"
else
    echo -e "${FAIL} Интернет по IP НЕ доступен"
fi

if ping -c 2 google.com >/dev/null 2>&1; then
    echo -e "${OK} DNS resolution работает"
else
    echo -e "${FAIL} DNS resolution НЕ работает"
fi

echo

echo "/etc/resolv.conf:"
echo

cat /etc/resolv.conf

echo

# ------------------------------------------------------------
# IP FORWARDING
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " IP FORWARDING"
echo "------------------------------------------------------"

sysctl net.ipv4.ip_forward

echo

if [[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]]; then
    echo -e "${OK} IPv4 forwarding включен"
else
    echo -e "${FAIL} IPv4 forwarding выключен"
fi

echo

# ------------------------------------------------------------
# IPTABLES BACKEND
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " IPTABLES BACKEND"
echo "------------------------------------------------------"

update-alternatives --display iptables || true

echo

CURRENT_BACKEND=$(update-alternatives --display iptables 2>/dev/null | grep "link currently points to" || true)

echo "${CURRENT_BACKEND}"

echo

if echo "${CURRENT_BACKEND}" | grep -q "iptables-nft"; then
    echo -e "${OK} Используется iptables-nft backend"
else
    echo -e "${WARN} Используется legacy backend"
fi

echo

# ------------------------------------------------------------
# NFTABLES RULESET
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " NFTABLES RULESET"
echo "------------------------------------------------------"

if systemctl is-active nftables >/dev/null 2>&1; then
    echo -e "${OK} nftables.service active"
else
    echo -e "${WARN} nftables.service inactive"
fi

echo

echo "Текущий nftables ruleset:"
echo

nft list ruleset || true

echo

# Проверяем NAT
if nft list ruleset 2>/dev/null | grep -qi masquerade; then
    echo -e "${OK} NAT masquerade найден"
else
    echo -e "${WARN} NAT masquerade НЕ найден"
fi

echo

# Проверяем SSH accept
if nft list ruleset 2>/dev/null | grep -q "dport ${SSH_PORT}"; then
    echo -e "${OK} SSH разрешен в nftables"
else
    echo -e "${WARN} SSH accept rule не обнаружен"
fi

echo

# ------------------------------------------------------------
# IPTABLES COMPAT
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " IPTABLES COMPATIBILITY"
echo "------------------------------------------------------"

echo "FILTER:"
echo

iptables -L -n -v || true

echo

echo "NAT:"
echo

iptables -t nat -L -n -v || true

echo

if iptables -t nat -L | grep -q MASQUERADE; then
    echo -e "${OK} MASQUERADE присутствует"
else
    echo -e "${WARN} MASQUERADE отсутствует"
fi

echo

# ------------------------------------------------------------
# DNSMASQ
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " DNSMASQ"
echo "------------------------------------------------------"

if systemctl is-active dnsmasq >/dev/null 2>&1; then
    echo -e "${OK} dnsmasq active"
else
    echo -e "${WARN} dnsmasq inactive"
fi

echo

systemctl --no-pager --full status dnsmasq || true

echo

echo "DHCP leases:"
echo

cat /var/lib/misc/dnsmasq.leases 2>/dev/null || true

echo
echo "------------------------------------------------------"
echo " PROXMOX FIREWALL SERVICES"
echo "------------------------------------------------------"

systemctl --no-pager --full status proxmox-firewall || true

echo
systemctl --no-pager --full status pve-firewall || true

echo
echo "------------------------------------------------------"
echo " PVE FIREWALL MANAGEMENT STATUS"
echo "------------------------------------------------------"

pve-firewall status || true

echo

# ------------------------------------------------------------
# FSTRIM
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " FSTRIM"
echo "------------------------------------------------------"

systemctl status fstrim.timer --no-pager || true

echo

# ------------------------------------------------------------
# VM NETWORK CONFIGS
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " VM NETWORK CONFIGS"
echo "------------------------------------------------------"

for VMID in $(qm list | awk 'NR>1 {print $1}'); do
    echo
    echo "VMID: ${VMID}"

    qm config "${VMID}" | grep -E 'net0|agent|ipconfig' || true
done

echo

# ------------------------------------------------------------
# RECOMMENDATIONS
# ------------------------------------------------------------

echo "------------------------------------------------------"
echo " RECOMMENDATIONS"
echo "------------------------------------------------------"

echo

if ! echo "${CURRENT_BACKEND}" | grep -q "iptables-nft"; then
    echo -e "${WARN} Рекомендуется перейти на nft backend:"
    echo
    echo "update-alternatives --set iptables /usr/sbin/iptables-nft"
    echo
fi

if ! nft list ruleset 2>/dev/null | grep -qi masquerade; then
    echo -e "${WARN} NAT masquerade отсутствует"
    echo
    echo "Проверьте NAT/firewall configuration."
    echo
fi

if [[ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]]; then
    echo -e "${WARN} IPv4 forwarding выключен"
    echo
    echo "sysctl -w net.ipv4.ip_forward=1"
    echo
fi

echo -e "${INFO} Аудит завершен"
echo
