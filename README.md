# SteamOS Bluetooth Fix

When running Steam with -steamos3 bluetooth can become disabled. So this watches for Steam with that flag to re-enable bluetooth should that happen. 

## Overview

This tool addresses common Bluetooth initialization issues on SteamOS by providing a reliable service that monitors and enables Bluetooth using multiple fallback methods. It's designed to be secure, lightweight, and compatible with SteamOS's read-only filesystem approach.

## Features

- **Multiple Bluetooth Control Methods**: Uses `bluetoothctl`, `dbus-send`, and `rfkill` with intelligent fallback
- **Secure Service**: Runs with minimal privileges and security hardening
- **Configurable Timing**: Customizable check intervals and maximum runtime
- **Comprehensive Logging**: Detailed logging via systemd journal
- **Automatic Startup**: Integrates with systemd for automatic startup at boot
- **Graceful Handling**: Exits cleanly when Bluetooth is already enabled

## Installation

### Prerequisites

- SteamOS or compatible Linux system
- Root access for installation
- systemd-based system

### Quick Install

1. Clone or download this repository
2. Make the install script executable:
   ```bash
   chmod +x install.sh
   ```
3. Run the installer as root:
   ```bash
   sudo ./install.sh
   ```

### Manual Installation

If you prefer to install manually:

1. Create the bluetooth user (if it doesn't exist):
   ```bash
   sudo useradd -r -s /bin/false -d /var/lib/bluetooth -c "Bluetooth service user" bluetooth
   ```

2. Copy the script to the system:
   ```bash
   sudo cp steamos-bluetooth-fix.sh /usr/local/bin/
   sudo chmod 755 /usr/local/bin/steamos-bluetooth-fix.sh
   sudo chown root:root /usr/local/bin/steamos-bluetooth-fix.sh
   ```

3. Install the systemd service:
   ```bash
   sudo cp steamos-bluetooth-fix.service /etc/systemd/system/
   sudo chmod 644 /etc/systemd/system/steamos-bluetooth-fix.service
   sudo chown root:root /etc/systemd/system/steamos-bluetooth-fix.service
   ```

4. Enable the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable steamos-bluetooth-fix.service
   ```

## Usage

### Service Management

After installation, the service will automatically start at boot. You can also manage it manually:

```bash
# Start the service
sudo systemctl start steamos-bluetooth-fix.service

# Check service status
sudo systemctl status steamos-bluetooth-fix.service

# View service logs
sudo journalctl -u steamos-bluetooth-fix.service -f

# Stop the service
sudo systemctl stop steamos-bluetooth-fix.service

# Disable automatic startup
sudo systemctl disable steamos-bluetooth-fix.service
```

### Manual Script Execution

You can also run the fix script manually:

```bash
sudo /usr/local/bin/steamos-bluetooth-fix.sh
```

## Configuration

The script includes several configurable parameters at the top of `steamos-bluetooth-fix.sh`:

- `INTERVAL`: Time between Bluetooth status checks (default: 5 seconds)
- `MAX_TIME`: Maximum runtime before giving up (default: 600 seconds / 10 minutes)
- `SCRIPT_NAME`: Name used for logging (default: "steamos_bluetooth_fix")

## How It Works

1. **Validation**: Checks configuration and available Bluetooth control commands
2. **Quick Check**: Immediately exits if Bluetooth is already enabled
3. **Multi-Method Approach**: Attempts to enable Bluetooth using:
   - `bluetoothctl power on`
   - D-Bus method calls to BlueZ
   - `rfkill unblock bluetooth`
4. **Retry Logic**: Continues attempting for up to 10 minutes with 5-second intervals
5. **Logging**: Provides detailed logs of all attempts and their results

## Security Features

The service implements several security hardening measures:

- **Minimal Privileges**: Runs as the `bluetooth` user, not root
- **Capability Restrictions**: Only has necessary network capabilities
- **System Call Filtering**: Blocks dangerous system calls
- **Filesystem Protection**: Read-only access to most of the filesystem
- **Memory Limits**: Restricted to 64MB of memory
- **Device Access Control**: Only allows access to required Bluetooth devices

## Troubleshooting

### Common Issues

1. **Service fails to start**:
   ```bash
   sudo journalctl -u steamos-bluetooth-fix.service -f
   ```
   Check the logs for specific error messages.

2. **Bluetooth still not working**:
   - Verify Bluetooth hardware is present: `lsusb` or `lspci`
   - Check if Bluetooth is hard-blocked: `rfkill list bluetooth`
   - Ensure BlueZ service is running: `systemctl status bluetooth.service`

3. **Permission errors**:
   - Ensure the bluetooth user exists: `id bluetooth`
   - Check file permissions: `ls -la /usr/local/bin/steamos-bluetooth-fix.sh`

### Debug Mode

For additional debugging, you can run the script manually with verbose output:

```bash
sudo bash -x /usr/local/bin/steamos-bluetooth-fix.sh
```

## Uninstallation

To remove the service:

```bash
sudo systemctl stop steamos-bluetooth-fix.service
sudo systemctl disable steamos-bluetooth-fix.service
sudo rm /etc/systemd/system/steamos-bluetooth-fix.service
sudo rm /usr/local/bin/steamos-bluetooth-fix.sh
sudo systemctl daemon-reload
```

## Contributing

Contributions are welcome! Please feel free to submit pull requests or open issues for bugs and feature requests.

### Development Guidelines

- Follow shell scripting best practices
- Maintain security hardening measures
- Add appropriate logging for new features
- Test on SteamOS when possible

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Support

If you encounter issues:

1. Check the [Troubleshooting](#troubleshooting) section
2. Review the service logs: `journalctl -u steamos-bluetooth-fix.service`
3. Open an issue on GitHub with detailed information about your system and the problem
