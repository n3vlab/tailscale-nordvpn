#!/bin/sh

set -x
#set -e

export PATH=/scripts:$PATH

# IP_NORDVPN environment variable is passed from docker-compose.yml
# e.g., 172.20.0.3

# Set the hostname for Tailscale (optional, but good for identification)
# Using INSTANCE_NAME for unique hostname if available, fallback to fixed name
TAILSCALE_HOSTNAME="tailnord-tailscale"
if [ -n "${INSTANCE_NAME}" ]; then
  TAILSCALE_HOSTNAME="tailnord-tailscale-${INSTANCE_NAME}"
fi

# Remove default route to avoid conflicts and set NordVPN container as gateway
echo "Removing default route and setting ${IP_NORDVPN} as gateway..."
ip route del default

# Wait for eth0 to be ready before adding route (optional but robust)
# Can add a loop here if eth0 might not be immediately available
# For Docker Compose, eth0 is usually ready quickly.
# Make sure to specify the correct network interface for the default route (eth0 in this setup).
ip route add default via "${IP_NORDVPN}" dev eth0

# Check if the route was added correctly
if [ $? -ne 0 ]; then
  echo "Error: Failed to add default route via ${IP_NORDVPN}. Exiting."
  exit 1
fi

# Run Tailscale 'up' command
# --advertise-exit-node: Advertise this node as an exit node (allowing other Tailscale devices to route traffic through it)
# --login-server: Specifies the control server to use (usually login.tailscale.com)
# --hostname: Sets the hostname for this Tailscale node
# --accept-routes: IMPORTANT! If you advertise routes (0.0.0.0/0 or ::/0) from this node for exit node functionality,
# you must also ensure that the Tailscale UI/CLI on *other* nodes accepts these routes.
# If this container is *only* acting as an exit node and nothing else, you might also add:
# --accept-routes --accept-dns # To fully utilize advertised routes and DNS settings
echo "Starting Tailscale..."
tailscale up \
  --hostname="${TAILSCALE_HOSTNAME}" \
  --advertise-exit-node \
  --login-server "${TAILSCALE_UP_LOGIN_SERVER}" \
  --accept-routes=false # Keep this false if this node is only an exit node and not accepting routes from others

# The 'Some peers are advertising routes but --accept-routes is false' warning
# means that other devices on your Tailscale network are advertising routes (like other exit nodes),
# but this container is not configured to use them. This is usually fine if this container is
# primarily serving as an exit node itself and not needing to route *through* other Tailscale nodes.

# Keep the script running to keep Tailscale alive
# tailscaled process usually takes over, but having a loop here can ensure the container stays up
# if tailscaled unexpectedly exits or command fails.
while true; do
  sleep 3600 # Sleep for 1 hour
  # You can add checks here, e.g., 'tailscale status'
done
