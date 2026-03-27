#!/bin/bash

echo "=== Network Setup Script ==="
echo "Running as user: $(whoami)"
echo "Quick network check for Capsule Agents..."

# Quick connectivity test
ping -c 1 8.8.8.8 > /dev/null 2>&1 && echo "✅ Network: OK" || echo "⚠️  Network: FAILED"

echo "Network setup completed successfully"
exit 0