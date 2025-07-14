#!/bin/bash

set -euo pipefail

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Create bluetooth user if it doesn't exist
if ! id -u bluetooth >/dev/null 2>&1; then
    echo "Creating bluetooth user..."
    useradd -r -s /bin/false -d /var/lib/bluetooth -c "Bluetooth service user" bluetooth
fi

# Install script
echo "Installing script..."
cp steamos-bluetooth-fix.sh /usr/local/bin/
chmod 755 /usr/local/bin/steamos-bluetooth-fix.sh
chown root:root /usr/local/bin/steamos-bluetooth-fix.sh

# Install service
echo "Installing service..."
cp steamos-bluetooth-fix.service /etc/systemd/system/
chmod 644 /etc/systemd/system/steamos-bluetooth-fix.service
chown root:root /etc/systemd/system/steamos-bluetooth-fix.service

# Enable service
systemctl daemon-reload
systemctl enable steamos-bluetooth-fix.service

echo "Installation complete!"
echo "We're enabled for next boot, starting now is possible but likely not needed."
echo "To start the service: systemctl start steamos-bluetooth-fix"
echo "To check status: systemctl status steamos-bluetooth-fix"
echo "To view logs: journalctl -u steamos-bluetooth-fix -f"