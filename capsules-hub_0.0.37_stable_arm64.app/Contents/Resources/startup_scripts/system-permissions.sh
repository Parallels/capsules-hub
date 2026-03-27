#!/bin/bash

echo "=== System Permissions Setup Script ==="
echo "Running as user: $(whoami)"
echo "Setting up directories for Capsule Agents..."

# Create required directories
APP_DATA_DIR="/tmp/capsule-agents"
mkdir -p "$APP_DATA_DIR/containers" "$APP_DATA_DIR/logs" && echo "✅ Created application directories" || echo "⚠️  Failed to create directories"

echo "System permissions setup completed successfully"
exit 0