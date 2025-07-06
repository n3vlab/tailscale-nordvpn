#!/bin/sh

set -x

ACTION=$1        # 'add' or 'del'
IP_SUBNET_VAR=$2 # The subnet passed from nordvpn_up.sh (e.g., 172.20.0.0/24)

# Ensure IP_SUBNET_VAR is provided
if [ -z "$IP_SUBNET_VAR" ]; then
  echo "Error: IP_SUBNET_VAR not provided to iptables_rules.sh"
  exit 1
fi

# Define the VPN interface name (usually tun0 or nordlynx)
# You might need to adjust this based on your NordVPN technology (e.g., tun for OpenVPN, nordlynx for NordLynx)
VPN_IFACE="tun0" # Common for OpenVPN. For NordLynx, it might be 'nordlynx' or similar.
                 # Check 'ip a' or 'ifconfig' inside the running NordVPN container to confirm.

# Flush existing custom rules for clarity, then apply new ones
# Note: Be careful with flushing. If not managing all rules, it can break existing connections.
# This assumes this script is the primary manager of these specific rules.
# iptables -F FORWARD # Use with extreme caution!

case "$ACTION" in
  add)
    echo "Adding iptables rules for subnet ${IP_SUBNET_VAR} via ${VPN_IFACE}..."
    # Allow forwarding from the Docker internal subnet (where Tailscale is) to the VPN tunnel
    iptables -A FORWARD -s "${IP_SUBNET_VAR}" -o "${VPN_IFACE}" -j ACCEPT
    # Allow forwarding from the VPN tunnel to the Docker internal subnet
    iptables -A FORWARD -i "${VPN_IFACE}" -d "${IP_SUBNET_VAR}" -j ACCEPT

    # Optional: If you need to masquerade traffic from the Docker subnet when it exits VPN
    # This might be already handled by NordVPN's internal routing/NAT, but can be added if issues arise.
    # iptables -t nat -A POSTROUTING -s "${IP_SUBNET_VAR}" -o "${VPN_IFACE}" -j MASQUERADE
    echo "Iptables rules added."
    ;;
  del)
    echo "Deleting iptables rules for subnet ${IP_SUBNET_VAR} via ${VPN_IFACE}..."
    # Delete the rules in reverse order of addition
    iptables -D FORWARD -i "${VPN_IFACE}" -d "${IP_SUBNET_VAR}" -j ACCEPT
    iptables -D FORWARD -s "${IP_SUBNET_VAR}" -o "${VPN_IFACE}" -j ACCEPT

    # Optional: Delete masquerade rule if it was added
    # iptables -t nat -D POSTROUTING -s "${IP_SUBNET_VAR}" -o "${VPN_IFACE}" -j MASQUERADE
    echo "Iptables rules deleted."
    ;;
  *)
    echo "Usage: $0 {add|del} <IP_SUBNET>"
    exit 1
    ;;
esac

# Persist iptables rules (if supported and needed, often not in ephemeral containers)
# /usr/sbin/iptables-save > /etc/iptables/rules.v4 # For iptables-persistent
