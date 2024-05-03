#!/bin/bash

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root"
    exit 1
fi

set -euo pipefail

# Colors for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Install packages if not already installed
install_packages() {
    local packages=("curl" "nano" "sudo" "cifs-utils" "cryptsetup-initramfs")
    apt-get update >/dev/null 2>&1
    apt-get install -y "${packages[@]}" >/dev/null 2>&1
}

# Remove and regenerate machine IDs
remove_regenerate_machine_ids() {
    echo -e "${GREEN}Removing and regenerating machine IDs...${NC}"
    rm -f /etc/machine-id
    dbus-uuidgen --ensure=/etc/machine-id

    rm /var/lib/dbus/machine-id
    dbus-uuidgen --ensure
}

# Remove SSH host keys and reconfigure openssh-server
remove_ssh_keys_reconfigure_openssh() {
    echo -e "${GREEN}Removing SSH host keys and reconfiguring openssh-server...${NC}"
    rm /etc/ssh/ssh_host_*
    dpkg-reconfigure openssh-server
}

# Change hostname and optionally update /etc/hosts with a new IP address
change_hostname() {
    old_hostname=$(hostname)
    read -p "Enter the new hostname [$old_hostname]: " new_hostname
    new_hostname=${new_hostname:-$old_hostname}

    read -p "Do you want to change the IP address? (y/n): " change_ip

    if [[ $change_ip == "y" ]]; then
        read -p "Enter the new IP address: " new_ip
    fi

    # Replace old entry with new entry in /etc/hosts
    if [[ $change_ip == "y" ]]; then
        sed -i "s/^[0-9.]*[[:space:]]*$old_hostname[[:space:]]*$/$new_ip $new_hostname/g" /etc/hosts
        echo -e "${GREEN}Changing hostname from $old_hostname to $new_hostname with new IP $new_ip in /etc/hosts...${NC}"
    else
        sed -i "s/^\([0-9.]*[[:space:]]*\)$old_hostname\([[:space:]]*\)$/\1$new_hostname\2/g" /etc/hosts
        echo -e "${GREEN}Changing hostname from $old_hostname to $new_hostname in /etc/hosts...${NC}"
    fi

    hostnamectl set-hostname "$new_hostname"
}

# Add user to sudo group
add_user_to_sudo() {
    read -p "Enter the username you want to add to the sudo group: " new_user
    echo -e "${GREEN}Adding $new_user to the sudo group...${NC}"
    usermod -aG sudo "$new_user"
}

# Disable root account
disable_root_account() {
    echo -e "${GREEN}Disabling root account...${NC}"
    passwd -d root
    passwd -l root
    usermod --expiredate 1 root
}

# Enable root account and set password
enable_set_password_root() {
    echo -e "${GREEN}Enabling root account and setting password...${NC}"
    usermod --expiredate "" root
    passwd root
}

# Add a new user
add_user() {
    read -p "Enter the username of the new user: " new_user
    adduser "$new_user"
}

# Delete a user
delete_user() {
    read -p "Enter the username of the user to delete: " del_user
    read -p "Are you sure you want to delete user $del_user? This action is irreversible. (y/n): " confirm
    if [[ $confirm == "y" ]]; then
        echo -e "${GREEN}Deleting user $del_user...${NC}"
        deluser --remove-home "$del_user"
    else
        echo "Deletion cancelled."
    fi
}

# Reboot system
reboot_system() {
    echo -e "${GREEN}Rebooting the system...${NC}"
    reboot
}

# Function to get the NAS password
get_nas_password() {
    local password
    prompt="Enter the NAS password: "
    while IFS= read -rp "$prompt" -s -n 1 char; do
        if [[ $char == $'\0' ]]; then
            break
        fi
        prompt='*'
        password+="$char"
    done
    echo "$password"
}

# Mount NAS share
mount_nas_share() {
    apt-get install cifs-utils
    read -p "Enter the NAS IP address: " nas_ip
    read -p "Enter the NAS share name: " share_name
    read -p "Enter the NAS username: " nas_username
    nas_password=$(get_nas_password)
    echo

    read -p "Enter the mount point or press Enter to use the default (/mnt/data_nas): " mount_point
    mount_point=${mount_point:-/mnt/data_nas}

    if [ ! -d "$mount_point" ]; then
        mkdir -p "$mount_point"
        echo -e "${GREEN}Created mount point: $mount_point${NC}"
    fi

    credentials_file="/root/.fsurps"
    echo "username=$nas_username" > "$credentials_file"
    echo "password=$nas_password" >> "$credentials_file"
    chmod 600 "$credentials_file"

    fstab_entry="//${nas_ip}/${share_name} $mount_point cifs rw,vers=3.0,credentials=$credentials_file,dir_mode=0775,file_mode=0775,uid=$(id -u),gid=$(id -g) 0 0"
    if ! grep -qF "$fstab_entry" /etc/fstab; then
        echo "$fstab_entry" >> /etc/fstab
    fi

    systemctl daemon-reload
    mount -a
    echo -e "${GREEN}NAS share mounted successfully${NC}"

    # Clean up password variable
    unset nas_password
}

# Set up LUKS encryption on a block device
setup_luks_encryption() {
    echo -e "This script will set up LUKS encryption on a block device."
    echo -e "Please ensure you have backups of your data before proceeding.\n"

    # List block devices and store the output in a variable
    lsblk_output=$(lsblk -o +FSTYPE)

    echo -e "\nAvailable block devices:"
    echo "$lsblk_output"

    # Prompt for the device path
    read -p "Enter the LUKS device path (e.g., /dev/nvme0n1p3): " device_path

    # Validate the device path
    if [[ ! -b $device_path ]]; then
        echo -e "${RED}Error:${NC} Invalid device path. Please enter a valid block device path (e.g., /dev/nvme0n1p3)." >&2
        exit 1
    fi

    # Extract the device name from the path (e.g., 'nvme0n1p3' from '/dev/nvme0n1p3')
    device_name=$(basename $device_path)

    # Securely create the directory for LUKS
    mkdir -p /etc/luks
    chmod 700 /etc/luks

    # Securely create the key file and set permissions
    touch /etc/luks/system.key
    chmod 400 /etc/luks/system.key
    dd if=/dev/urandom of=/etc/luks/system.key bs=4096 count=1 iflag=fullblock

    # Verify the key file
    echo -e "\nKey file created:"
    ls -l /etc/luks/system.key

    # Add the key to the LUKS device
    cryptsetup luksAddKey "$device_path" /etc/luks/system.key

    # Install cryptsetup for initramfs
    apt install -y cryptsetup-initramfs

    # Configure the keyfile pattern
    echo 'KEYFILE_PATTERN="/etc/luks/*.key"' | tee -a /etc/cryptsetup-initramfs/conf-hook > /dev/null

    # Set UMASK in initramfs.conf
    echo 'UMASK=0077' | tee -a /etc/initramfs-tools/initramfs.conf > /dev/null

    # Clear existing entries in crypttab
    truncate --size 0 /etc/crypttab

    # Add entry to crypttab
    uuid=$(blkid -s UUID -o value $device_path)
    echo "${device_name}_crypt UUID=$uuid /etc/luks/system.key luks" | tee -a /etc/crypttab > /dev/null

    # Update initramfs
    update-initramfs -u -k all > /dev/null

    echo -e "\n${GREEN}LUKS encryption setup complete.${NC}"
}

# Perform all actions for Ubuntu
perform_all_actions_ubuntu() {
    remove_regenerate_machine_ids
    remove_ssh_keys_reconfigure_openssh
    change_hostname
    add_user
    reboot_system
}

# Perform all actions for Debian
perform_all_actions_debian() {
    remove_regenerate_machine_ids
    remove_ssh_keys_reconfigure_openssh
    change_hostname
    add_user_to_sudo
    reboot_system
}

# Perform all actions
perform_all_actions() {
    read -p "Enter your Linux distribution (ubuntu/debian): " distro
    case $distro in
        ubuntu) perform_all_actions_ubuntu ;;
        debian) perform_all_actions_debian ;;
        *) echo -e "${RED}Invalid distribution. Please enter 'ubuntu' or 'debian'.${NC}" ;;
    esac
}

# Main menu
#!/bin/bash

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root"
    exit 1
fi

set -euo pipefail

# Colors for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Install packages if not already installed
install_packages() {
    local packages=("curl" "nano" "sudo" "cifs-utils" "cryptsetup-initramfs")
    apt-get update >/dev/null 2>&1
    apt-get install -y "${packages[@]}" >/dev/null 2>&1
}

# Remove and regenerate machine IDs
remove_regenerate_machine_ids() {
    echo -e "${GREEN}Removing and regenerating machine IDs...${NC}"
    rm -f /etc/machine-id
    dbus-uuidgen --ensure=/etc/machine-id

    rm /var/lib/dbus/machine-id
    dbus-uuidgen --ensure
}

# Remove SSH host keys and reconfigure openssh-server
remove_ssh_keys_reconfigure_openssh() {
    echo -e "${GREEN}Removing SSH host keys and reconfiguring openssh-server...${NC}"
    rm /etc/ssh/ssh_host_*
    dpkg-reconfigure openssh-server
}

# Change hostname and optionally update /etc/hosts with a new IP address
change_hostname() {
    old_hostname=$(hostname)
    read -p "Enter the new hostname [$old_hostname]: " new_hostname
    new_hostname=${new_hostname:-$old_hostname}

    read -p "Do you want to change the IP address? (y/n): " change_ip

    if [[ $change_ip == "y" ]]; then
        read -p "Enter the new IP address: " new_ip
    fi

    # Replace old entry with new entry in /etc/hosts
    if [[ $change_ip == "y" ]]; then
        sed -i "s/^[0-9.]*[[:space:]]*$old_hostname[[:space:]]*$/$new_ip $new_hostname/g" /etc/hosts
        echo -e "${GREEN}Changing hostname from $old_hostname to $new_hostname with new IP $new_ip in /etc/hosts...${NC}"
    else
        sed -i "s/^\([0-9.]*[[:space:]]*\)$old_hostname\([[:space:]]*\)$/\1$new_hostname\2/g" /etc/hosts
        echo -e "${GREEN}Changing hostname from $old_hostname to $new_hostname in /etc/hosts...${NC}"
    fi

    hostnamectl set-hostname "$new_hostname"
}

# Add user to sudo group
add_user_to_sudo() {
    read -p "Enter the username you want to add to the sudo group: " new_user
    echo -e "${GREEN}Adding $new_user to the sudo group...${NC}"
    usermod -aG sudo "$new_user"
}

# Disable root account
disable_root_account() {
    echo -e "${GREEN}Disabling root account...${NC}"
    passwd -d root
    passwd -l root
    usermod --expiredate 1 root
}

# Enable root account and set password
enable_set_password_root() {
    echo -e "${GREEN}Enabling root account and setting password...${NC}"
    usermod --expiredate "" root
    passwd root
}

# Add a new user
add_user() {
    read -p "Enter the username of the new user: " new_user
    adduser "$new_user"
}

# Delete a user
delete_user() {
    read -p "Enter the username of the user to delete: " del_user
    read -p "Are you sure you want to delete user $del_user? This action is irreversible. (y/n): " confirm
    if [[ $confirm == "y" ]]; then
        echo -e "${GREEN}Deleting user $del_user...${NC}"
        deluser --remove-home "$del_user"
    else
        echo "Deletion cancelled."
    fi
}

# Reboot system
reboot_system() {
    echo -e "${GREEN}Rebooting the system...${NC}"
    reboot
}

# Function to get the NAS password
get_nas_password() {
    local password
    prompt="Enter the NAS password: "
    while IFS= read -rp "$prompt" -s -n 1 char; do
        if [[ $char == $'\0' ]]; then
            break
        fi
        prompt='*'
        password+="$char"
    done
    echo "$password"
}

# Mount NAS share
mount_nas_share() {
    read -p "Enter the NAS IP address: " nas_ip
    read -p "Enter the NAS share name: " share_name
    read -p "Enter the NAS username: " nas_username
    nas_password=$(get_nas_password)
    echo

    read -p "Enter the mount point or press Enter to use the default (/mnt/data_nas): " mount_point
    mount_point=${mount_point:-/mnt/data_nas}

    if [ ! -d "$mount_point" ]; then
        mkdir -p "$mount_point"
        echo -e "${GREEN}Created mount point: $mount_point${NC}"
    fi

    credentials_file="/root/.fsurps"
    echo "username=$nas_username" > "$credentials_file"
    echo "password=$nas_password" >> "$credentials_file"
    chmod 600 "$credentials_file"

    fstab_entry="//${nas_ip}/${share_name} $mount_point cifs rw,vers=3.0,credentials=$credentials_file,dir_mode=0775,file_mode=0775,uid=$(id -u),gid=$(id -g) 0 0"
    if ! grep -qF "$fstab_entry" /etc/fstab; then
        echo "$fstab_entry" >> /etc/fstab
    fi

    mount -a
    echo -e "${GREEN}NAS share mounted successfully${NC}"

    # Clean up password variable
    unset nas_password
}

# Set up LUKS encryption on a block device
setup_luks_encryption() {
    echo -e "This script will set up LUKS encryption on a block device."
    echo -e "Please ensure you have backups of your data before proceeding.\n"

    # List block devices and store the output in a variable
    lsblk_output=$(lsblk -o +FSTYPE)

    echo -e "\nAvailable block devices:"
    echo "$lsblk_output"

    # Prompt for the device path
    read -p "Enter the LUKS device path (e.g., /dev/nvme0n1p3): " device_path

    # Validate the device path
    if [[ ! -b $device_path ]]; then
        echo -e "${RED}Error:${NC} Invalid device path. Please enter a valid block device path (e.g., /dev/nvme0n1p3)." >&2
        exit 1
    fi

    # Extract the device name from the path (e.g., 'nvme0n1p3' from '/dev/nvme0n1p3')
    device_name=$(basename $device_path)

    # Securely create the directory for LUKS
    mkdir -p /etc/luks
    chmod 700 /etc/luks

    # Securely create the key file and set permissions
    touch /etc/luks/system.key
    chmod 400 /etc/luks/system.key
    dd if=/dev/urandom of=/etc/luks/system.key bs=4096 count=1 iflag=fullblock

    # Verify the key file
    echo -e "\nKey file created:"
    ls -l /etc/luks/system.key

    # Add the key to the LUKS device
    cryptsetup luksAddKey "$device_path" /etc/luks/system.key

    # Install cryptsetup for initramfs
    apt install -y cryptsetup-initramfs

    # Configure the keyfile pattern
    echo 'KEYFILE_PATTERN="/etc/luks/*.key"' | tee -a /etc/cryptsetup-initramfs/conf-hook > /dev/null

    # Set UMASK in initramfs.conf
    echo 'UMASK=0077' | tee -a /etc/initramfs-tools/initramfs.conf > /dev/null

    # Clear existing entries in crypttab
    truncate --size 0 /etc/crypttab

    # Add entry to crypttab
    uuid=$(blkid -s UUID -o value $device_path)
    echo "${device_name}_crypt UUID=$uuid /etc/luks/system.key luks" | tee -a /etc/crypttab > /dev/null

    # Update initramfs
    update-initramfs -u -k all > /dev/null

    echo -e "\n${GREEN}LUKS encryption setup complete.${NC}"
}

# Perform all actions for Ubuntu
perform_all_actions_ubuntu() {
    remove_regenerate_machine_ids
    remove_ssh_keys_reconfigure_openssh
    change_hostname
    add_user
    reboot_system
}

# Perform all actions for Debian
perform_all_actions_debian() {
    remove_regenerate_machine_ids
    remove_ssh_keys_reconfigure_openssh
    change_hostname
    add_user_to_sudo
    reboot_system
}

# Perform all actions
perform_all_actions() {
    read -p "Enter your Linux distribution (ubuntu/debian): " distro
    case $distro in
        ubuntu) perform_all_actions_ubuntu ;;
        debian) perform_all_actions_debian ;;
        *) echo -e "${RED}Invalid distribution. Please enter 'ubuntu' or 'debian'.${NC}" ;;
    esac
}

# Main menu
main_menu() {
    while true; do
        echo -e "\n=== Main Menu ==="
        echo "1. Install Packages"
        echo "2. Remove and Regenerate Machine IDs"
        echo "3. Remove SSH Host Keys and Reconfigure OpenSSH"
        echo "4. Change Hostname and Optionally Update /etc/hosts with a New IP Address"
        echo "5. Add User to Sudo Group"
        echo "6. Disable Root Account"
        echo "7. Enable Root Account and Set Password"
        echo "8. Add a New User"
        echo "9. Delete a User"
        echo "10. Reboot System"
        echo "11. Mount NAS Share"
        echo "12. Set Up LUKS Encryption on a Block Device"
        echo "13. Perform All Actions"
        echo "14. Quit"

        read -p "Enter your choice (1-14): " choice
        case $choice in
            1) install_packages ;;
            2) remove_regenerate_machine_ids ;;
            3) remove_ssh_keys_reconfigure_openssh ;;
            4) change_hostname ;;
            5) add_user_to_sudo ;;
            6) disable_root_account ;;
            7) enable_set_password_root ;;
            8) add_user ;;
            9) delete_user ;;
            10) reboot_system ;;
            11) mount_nas_share ;;
            12) setup_luks_encryption ;;
            13) perform_all_actions ;;
            14) echo "Exiting."; exit ;;
            *) echo -e "${RED}Invalid option. Please select a valid option.${NC}" ;;
        esac
        echo "Press Enter to return to the main menu..."
        read -s -n 1
    done
}

# Run the main menu
main_menu

echo "Action complete."


# Run the main menu
main_menu

echo "Action complete."
