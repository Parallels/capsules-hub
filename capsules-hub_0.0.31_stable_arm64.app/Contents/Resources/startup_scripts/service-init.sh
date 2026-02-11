#!/bin/bash

echo "=== Service Initialization Script ==="
echo "Running as user: $(whoami)"
echo "Initializing services for Capsule Agents..."

# Create basic config and state files
CONFIG_FILE="/tmp/capsule-agents/service.conf"
echo "# Capsule Agents Config - $(date)" > "$CONFIG_FILE"
echo "version=0.0.2" >> "$CONFIG_FILE"

STATE_FILE="/tmp/capsule-agents/service.state"
echo "{\"initialized\": true, \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > "$STATE_FILE"

# Create startup completion marker
touch "/tmp/capsule-agents/startup_completed"

echo "✅ Created configuration files"
echo "Service initialization completed successfully"
exit 0