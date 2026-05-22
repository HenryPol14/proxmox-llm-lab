# Network Architecture

## Bridges

vmbr0 -> WAN/public
vmbr1 -> NAT internal AI network

## DHCP/DNS

dnsmasq on vmbr1

## NAT

iptables-nft masquerade

## Validation

Run:

./scripts/11-audit-network.sh
