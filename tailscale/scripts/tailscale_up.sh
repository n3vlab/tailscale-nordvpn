#!/bin/sh

set -x
#set -e # It's often safer to keep 'set -e' commented out for debugging in long-running scripts.

export PATH=/scripts:$PATH

# IP_NORDVPN environment variable is passed from docker-compose.yml
# e.g., 172.20.0.3

# Set the hostname for Tailscale (optional, but good for identification)
# Using INSTANCE_NAME for unique hostname if available, fallback to fixed name
TAILSCALE_HOSTNAME="tailnord-tailscale"
if [ -n "${INSTANCE_NAME}" ]; then
  TAILSCALE_HOSTNAME="tailnord-tailscale-${INSTANCE_NAME}"
fi

# IMPORTANT: Ensure tailscaled is running before attempting 'tailscale up'
# The 'tailscaled' daemon must be started. If it's not part of the base image's entrypoint,
# you must start it here.
# Check if it's already running. If not, start it in the background.
echo "Checking if tailscaled daemon is running..."
if ! pgrep tailscaled > /dev/null; then
  echo "tailscaled not running, starting it now..."
  # Start tailscaled in the background with --cleanup for a clean state
  /usr/bin/tailscaled --cleanup &
  # Give it a moment to initialize before trying to 'up'
  sleep 5 # Adjust this sleep time if necessary (e.g., 10 seconds)
else
  echo "tailscaled is already running."
fi

# Remove default route to avoid conflicts and set NordVPN container as gateway
echo "Removing default route and setting ${IP_NORDVPN} as gateway..."
# '|| true' ensures the script continues even if 'ip route del default' fails (e.g., no default route exists yet).
ip route del default || true

# Wait for eth0 to be ready before adding route (optional but robust)
# For Docker Compose, eth0 is usually ready quickly.
# Make sure to specify the correct network interface for the default route (eth0 in this setup).
echo "Adding default route via ${IP_NORDVPN} on eth0..."
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

# Check the exit status of tailscale up
if [ $? -ne 0 ]; then
  echo "Error: tailscale up command failed. Check Tailscale logs."
  # You might want to add a loop here to retry 'tailscale up' if it fails initially
  # For now, we'll let the container stay alive for debugging.
fi

# The 'Some peers are advertising routes but --accept-routes is false' warning
# means that other devices on your Tailscale network are advertising routes (like other exit nodes),
# but this container is not configured to use them. This is usually fine if this container is
# primarily serving as an exit node itself and not needing to route *through* other Tailscale nodes.

# Keep the script running to keep Tailscale alive
# The 'tailscaled' process runs in the background. This loop ensures the shell script (which is the main container process)
# continues to run, thus keeping the container alive. If this script exits, the container will stop.
echo "Tailscale setup complete. Keeping container alive..."
while true; do
  sleep 3600 # Sleep for 1 hour
  # Optional: Add periodic health checks here, e.g., 'tailscale status'
done
