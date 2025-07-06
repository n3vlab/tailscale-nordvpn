#!/bin/sh

set -x
#set -e # It's often safer to keep 'set -e' commented out for debugging in long-running scripts.

export PATH=/scripts:$PATH

# Define default reconnect period in hours, convert to seconds
RECONNECT_AFTER_HOURS=${RECONNECT_AFTER_HOURS:-1}
RECONNECT_AFTER_SECONDS=$(($RECONNECT_AFTER_HOURS * 60 * 60))

# Default NordVPN endpoint if not set via environment variable
# Uses NORDVPN_ENDPOINT from .env, falls back to 'us' if not set
ENDPOINT=${NORDVPN_ENDPOINT:-us}

# Check if NordVPN token is provided
if [ -z "$NORDVPN_TOKEN" ]; then
  echo "NORDVPN_TOKEN environment variable is unset. Exiting."
  exit 1 # Use exit 1 for error conditions
fi

# Not strictly necessary for Docker images, as iptables-legacy is usually default or handled.
# update-alternatives --set iptables /usr/sbin/iptables-legacy

# Function to wait for the NordVPN daemon to start
wait_for_nordvpn_daemon() {
  echo "Waiting for NordVPN daemon..."
  try=5 # Increased retries
  while [ "$try" -gt 0 ]; do
    nordvpn status > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      echo "NordVPN daemon is running."
      return 0
    fi
    echo "NordVPN daemon not ready, retrying in 3 seconds..."
    sleep 3

    try=$((try - 1))
    if [ $try -eq 0 ]; then
      echo "NordVPN daemon failed to start within expected time. Attempting restart."
      /etc/init.d/nordvpn stop
      sleep 2
      /etc/init.d/nordvpn start
      try=5 # Reset tries after restart attempt
    fi
  done
  echo "Failed to start NordVPN daemon. Exiting."
  exit 1
}

# Function to connect to NordVPN
nordvpn_connect() {
  echo "Attempting to connect to NordVPN endpoint: $ENDPOINT"
  try=5 # Increased retries
  while [ "$try" -gt 0 ]; do
    nordvpn connect $ENDPOINT
    if [ $? -eq 0 ]; then
      echo "Successfully connected to NordVPN."
      # Call iptables_rules.sh to add necessary rules, passing the subnet
      bash /scripts/iptables_rules.sh add "${IP_SUBNET}" # Pass IP_SUBNET to iptables script
      return 0
    fi
    echo "NordVPN connection failed, retrying in 5 seconds..."
    sleep 5 # Increased sleep for connection retries

    try=$((try - 1))
    if [ $try -eq 0 ]; then
      echo "Cannot connect to NordVPN after multiple attempts. Sleeping for 5 minutes and retrying."
      sleep 300 # Sleep for 5 minutes (300 seconds)
      # Do not exit here, just retry connecting again after a longer break
      try=5 # Reset tries after long sleep
    fi
  done
}

# --- Main script execution starts here ---

echo "Starting NordVPN daemon..."
/etc/init.d/nordvpn start
ps auxwwf # Show running processes

wait_for_nordvpn_daemon

# Turn off analytics
echo "Setting NordVPN analytics to off..."
nordvpn set analytics off

echo "Current NordVPN status:"
nordvpn status

echo "Checking NordVPN account status..."
nordvpn account
if [ $? -ne 0 ]; then # Changed from 'eq 1' to 'ne 0' for robust error checking
  echo "Logging in to NordVPN..."
  nordvpn login --token "$NORDVPN_TOKEN"
  if [ $? -ne 0 ]; then
    echo "NordVPN login failed. Exiting."
    exit 1
  fi
fi

# Set VPN technology and protocol based on environment variables
echo "Setting NordVPN technology to: ${NORDVPN_TECHNOLOGY:=openvpn}" # Default to openvpn if not set
nordvpn set technology "$NORDVPN_TECHNOLOGY"

if [ "$NORDVPN_TECHNOLOGY" = "openvpn" ]; then
  echo "Setting OpenVPN protocol to: ${NORDVPN_OPENVPN_PROTOCOL:=tcp}" # Default to tcp if not set
  nordvpn set protocol "$NORDVPN_OPENVPN_PROTOCOL"
fi

# Allowlist the Docker internal subnet (for Tailscale traffic)
echo "Adding subnet ${IP_SUBNET} to NordVPN allowlist..."
nordvpn allowlist add subnet "${IP_SUBNET}"

# Enable auto-connect to persist through reboots
echo "Setting NordVPN autoconnect to on..."
nordvpn set autoconnect on

# Enable kill switch (WARNING: This will block all traffic if VPN disconnects)
echo "Setting NordVPN killswitch to on..."
nordvpn set killswitch on

# Connect to NordVPN
nordvpn_connect

# Final connection status check
echo "NordVPN connection established. Current status:"
nordvpn status

# Other options to consider (uncomment if desired):
# echo "Setting NordVPN cybersec to on..."
# nordvpn set cybersec on
# echo "Setting NordVPN obfuscate to on..."
# nordvpn set obfuscate on
# echo "Setting NordVPN notify to on..."
# nordvpn set notify on

echo "NordVPN reconnect period: ${RECONNECT_AFTER_SECONDS}s"

# Start the web application (if any) in the background
# Make sure /webapp/app.py exists and is executable
# nohup python3 /webapp/app.py &

# Main loop for periodic reconnection
while [ 1 ]; do
  sleep "$RECONNECT_AFTER_SECONDS"
  echo "--- $(date +%Y%m%d_%H%M%S) ---"
  echo "Reconnecting to a different server. Next reconnect in ${RECONNECT_AFTER_SECONDS}s."
  date
  echo "Current NordVPN status before disconnect:"
  nordvpn status
  echo "Disconnecting from NordVPN..."
  nordvpn disconnect
  # Call iptables_rules.sh to delete previous rules before reconnecting
  bash /scripts/iptables_rules.sh del "${IP_SUBNET}" # Pass IP_SUBNET to iptables script
  sleep 1
  echo "Attempting to reconnect NordVPN..."
  nordvpn_connect
  echo "Reconnection attempt finished."
  echo
done
