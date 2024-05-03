System Administration and Automation Script

This script provides a comprehensive menu-driven interface for performing essential system administration tasks and automations on Debian and Ubuntu systems. It is designed to simplify and streamline common system management operations.

Usage:

Run the script as the root user: sudo bash system_setup.sh.
Follow the on-screen instructions to select and execute actions.
Options:

Install Packages: Installs necessary packages (curl, nano, sudo, cifs-utils, cryptsetup-initramfs).
Remove and Regenerate Machine IDs: Removes and regenerates machine IDs (/etc/machine-id, /var/lib/dbus/machine-id).
Remove SSH Host Keys and Reconfigure OpenSSH: Removes SSH host keys and reconfigures the OpenSSH server.
Change Hostname: Changes the system hostname and optionally updates /etc/hosts with a new IP address.
Add User to Sudo Group: Adds a user to the sudo group for administrative privileges.
Disable Root Account: Disables the root account to enhance system security.
Enable Root Account and Set Password: Enables the root account and sets a password for it.
Add a New User: Interactively adds a new user to the system.
Delete a User: Deletes a specified user account from the system (irreversible action).
Reboot System: Safely reboots the system to apply changes.
Mount NAS Share: Guides you through mounting a Network Attached Storage (NAS) share.
Set Up LUKS Encryption on a Block Device: Configures LUKS encryption for a specified block device.
Perform All Actions: Sequentially performs all available actions for system setup and configuration.
Quit: Exits the script.
Important:

Carefully follow the instructions and confirm actions before proceeding, especially for irreversible operations like deleting users.
Ensure you have backups of critical data before making any changes that could result in data loss.
