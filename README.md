# System Administration and Automation Script

This script provides a comprehensive menu-driven interface for performing essential system administration tasks and automations on Debian and Ubuntu systems. It is designed to simplify and streamline common system management operations, making it particularly useful for setting up and configuring virtual machine (VM) clones.

## Usage

1. Run the script as the root user:
 
   ```bash
   sudo bash -c "$(wget -qLO - https://raw.githubusercontent.com/Fa-r27-aD/LinuxMegaTools/main/lmt.sh)"
   ```
   ```bash
   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Fa-r27-aD/LinuxMegaTools/main/lmt.sh)"
   ```
   
2. Follow the on-screen instructions to select and execute actions.

## Options

1. **Install Packages:** Installs necessary packages (`curl`, `nano`, `sudo`, `cifs-utils`, `cryptsetup-initramfs`).
2. **Remove and Regenerate Machine IDs:** Removes and regenerates machine IDs (`/etc/machine-id`, `/var/lib/dbus/machine-id`).
3. **Remove SSH Host Keys and Reconfigure OpenSSH:** Removes SSH host keys and reconfigures the OpenSSH server.
4. **Change Hostname:** Changes the system hostname and optionally updates `/etc/hosts` with a new IP address.
5. **Add User to Sudo Group:** Adds a user to the sudo group for administrative privileges.
6. **Disable Root Account:** Disables the root account to enhance system security.
7. **Enable Root Account and Set Password:** Enables the root account and sets a password for it.
8. **Add a New User:** Interactively adds a new user to the system.
9. **Delete a User:** Deletes a specified user account from the system (irreversible action).
10. **Reboot System:** Safely reboots the system to apply changes.
11. **Mount NAS Share:** Guides you through mounting a Network Attached Storage (NAS) share.
12. **Set Up LUKS Encryption on a Block Device:** Configures LUKS encryption for a specified block device.
13. **Perform All Actions:** Sequentially performs all available actions for system setup and configuration.
14. **Quit:** Exits the script.

## Important

- Carefully follow the instructions and confirm actions before proceeding, especially for irreversible operations like deleting users.
- Ensure you have backups of critical data before making any changes that could result in data loss.

## Note for VM Cloning

- This script is particularly useful for setting up and configuring cloned virtual machines, as it automates many common setup tasks and ensures consistency across VM instances.
