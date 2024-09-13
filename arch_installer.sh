#!/bin/bash

# Define variables
DISK="/dev/nvme0n1"
HOSTNAME="archlinux"

# Prompt for passwords and additional user details
read -p "Enter root password: " ROOT_PASSWORD
read -p "Enter username for additional user: " USER
read -sp "Enter password for $USER: " USER_PASSWORD
echo
read -p "Should $USER have sudo privileges? (y/n): " SUDO_PRIVILEGES

# Set the timezone
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc

# Update the system clock
timedatectl set-ntp true

# Partition the disk using fdisk
(
echo g # Create a new GPT partition table
echo n # Add a new partition
echo 1 # Partition number
echo # Default - start at the beginning
echo +512M # Size of the boot partition
echo t # Change partition type
echo 1 # Partition type (EFI System)
echo n # Add a new partition
echo 2 # Partition number
echo # Default - start after the boot partition
echo +8G # Size of the swap partition
echo t # Change partition type
echo 19 # Partition type (Linux swap)
echo n # Add a new partition
echo 3 # Partition number
echo # Default - start after the swap partition
echo # Use the rest of the disk for root
echo w # Write changes and exit
) | fdisk $DISK

# Format the partitions
mkfs.fat -F32 ${DISK}p1
mkswap ${DISK}p2
mkfs.btrfs ${DISK}p3

# Mount the partitions
mount ${DISK}p3 /mnt
mkdir /mnt/boot
mount ${DISK}p1 /mnt/boot
swapon ${DISK}p2

# Install base system
pacstrap /mnt base base-devel linux linux-firmware btrfs-progs vim zsh

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt /bin/bash <<EOF
# Set hostname
echo "$HOSTNAME" > /etc/hostname

# Set up locale
sed -i 's/#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Create a new user
useradd -m -G wheel -s /bin/zsh $USER
echo "$USER:$USER_PASSWORD" | chpasswd

# Configure sudo
pacman -S sudo --noconfirm
if [ "$SUDO_PRIVILEGES" = "y" ]; then
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
else
    echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
fi

# Install GRUB and os-prober
pacman -S grub os-prober --noconfirm

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub
grub-mkconfig -o /boot/grub/grub.cfg

# Install yay and other AUR packages
pacman -S git --noconfirm
cd /tmp
git clone https://aur.archlinux.org/yay-git.git
cd yay-git
makepkg -si --noconfirm
cd ..
rm -rf yay-git

# Install all required packages
yay -S hyprland swaybg alacritty wlroots mesa vulkan-radeon libva-mesa-driver mesa-vdpau waybar rofi xdg-desktop-portal swaylock tmux ranger neovim nano btop zsh zsh-syntax-highlighting git gcc clang cmake python nodejs npm rust pipewire pipewire-pulse wireplumber pavucontrol pamixer alsa-utils bluez bluez-utils blueman pipewire-bluetooth wl-clipboard clipman steam lutris proton mpv vlc imagemagick syncthing rclone tlp upower acpid nerd-fonts arc-theme papirus-icon-theme mako grim slurp swappy wf-recorder ufw fail2ban rsync timeshift neofetch python-pywal16 --noconfirm

# Enable services
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable pipewire pipewire-pulse wireplumber
systemctl enable tlp
systemctl enable ufw
systemctl enable syncthing@$USER
systemctl enable acpid
systemctl enable timeshift-autosnap
systemctl enable mako

# Start services
systemctl start NetworkManager
systemctl start bluetooth
systemctl start pipewire pipewire-pulse wireplumber
systemctl start tlp
systemctl start ufw
systemctl start syncthing@$USER
systemctl start acpid
systemctl start timeshift-autosnap
systemctl start mako

# Set up zsh configuration
su - $USER -c "sh -c \"$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""

# Optionally copy a basic .zshrc to the new user's home
cat <<EOL > /home/$USER/.zshrc
# Example .zshrc configuration
export ZSH="/home/$USER/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git zsh-syntax-highlighting)
source \$ZSH/oh-my-zsh.sh
EOL
chown $USER:$USER /home/$USER/.zshrc

# Exit chroot
EOF

# Unmount partitions and reboot
umount -R /mnt
reboot
