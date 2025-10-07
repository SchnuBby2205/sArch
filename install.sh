#!/bin/bash
scriptname=$(basename "$0")
logFile="/var/log/ArchInstall.log"
RED="\e[31m" GREEN="\e[32m" YELLOW="\e[1;33m" WHITE="\e[1;37m" NC="\e[0m"
CROSS="\u2717" CHECK="\u2713"
RUNNING="${YELLOW}•${NC}" ERROR="${RED}${CROSS}${NC}" MYOK="${GREEN}${CHECK}${NC}"
UP="\e[A" CLEAR="\r                                        \r"
Banner() {
  clear
  myPrint print green ".▄▄ ·  ▄▄·  ▄ .▄ ▐ ▄ ▄• ▄▌▄▄▄▄· ▄▄▄▄·  ▄· ▄▌            \n"
  myPrint print green "▐█ ▀. ▐█ ▌▪██▪▐█•█▌▐██▪██▌▐█ ▀█▪▐█ ▀█▪▐█▪██▌            \n"
  myPrint print green "▄▀▀▀█▄██ ▄▄██▀▐█▐█▐▐▌█▌▐█▌▐█▀▀█▄▐█▀▀█▄▐█▌▐█▪            \n"
  myPrint print green "▐█▄▪▐█▐███▌██▌▐▀██▐█▌▐█▄█▌██▄▪▐███▄▪▐█ ▐█▀·.            \n"
  myPrint print green " ▀▀▀▀ ·▀▀▀ ▀▀▀ ·▀▀ █▪ ▀▀▀ ·▀▀▀▀ ·▀▀▀▀   ▀ •             \n"
  myPrint print green " ▄▄▄· ▄▄▄   ▄▄·  ▄ .▄▪   ▐ ▄ .▄▄ · ▄▄▄▄▄ ▄▄▄· ▄▄▌  ▄▄▌  \n"
  myPrint print green "▐█ ▀█ ▀▄ █·▐█ ▌▪██▪▐███ •█▌▐█▐█ ▀. •██  ▐█ ▀█ ██•  ██•  \n"
  myPrint print green "▄█▀▀█ ▐▀▀▄ ██ ▄▄██▀▐█▐█·▐█▐▐▌▄▀▀▀█▄ ▐█.▪▄█▀▀█ ██▪  ██▪  \n"
  myPrint print green "▐█ ▪▐▌▐█•█▌▐███▌██▌▐▀▐█▌██▐█▌▐█▄▪▐█ ▐█▌·▐█ ▪▐▌▐█▌▐▌▐█▌▐▌\n"
  myPrint print green " ▀  ▀ .▀  ▀·▀▀▀ ▀▀▀ ·▀▀▀▀▀ █▪ ▀▀▀▀  ▀▀▀  ▀  ▀ .▀▀▀ .▀▀▀ \n\n"
}
#TESTEN: function myPrint() { local c=$1 m=$2; printf "%b" "${!c^^}${m}${NC:-}"; }
myPrint(){ case "$1" in
  step) [ "$2" = ok ] && printf "${CLEAR}${UP}${CLEAR}" || printf "${RUNNING} $2 ${WHITE}$3${NC}\n";;
  countdown) for((i=$2;i>0;i--));do myPrint print green "\r$3 $i..."; sleep 1; done; echo;;
  print) c=${2^^}; printf "%b" "${!c}${3}${NC:-}";;  
esac; }
exitWithError() { printf "\n${ERROR} %s\n" "$1"; exit 1; }
getInput(){ local p=$1 v=$2 d=$3 i; printf "${YELLOW}${p} ${NC}"; read -r i; printf -v "$v" "%s" "${i:-$d}"; [[ -z "${!v}" ]] && exitWithError "Input value can not be empty!"; }
myPasswd() {
  for ((a=0; a<3; a++)); do
    read -s -p "Password: " p1; echo
    read -s -p "Retype: " p2; echo
    [[ "$p1" != "$p2" || -z "$p1" ]] && echo "Passwords didn't match." && continue
    echo "$1:$p1" | sudo chpasswd && { myPrint print yellow "\nPassword updated successfully.\n"; return; }
    exitWithError "Error setting the password."
  done
  myPrint print red "Maximum tries reached. Script will end now."; exit 1
}
runCFDiskIfNeeded(){ 
  [[ -z "$cfdisk" && -n "$disk" ]] && getInput "\nStart cfdisk (y/N) ?\n" cfdisk "N"
  [[ "$cfdisk" =~ ^[yY]$ ]] && { 
    [[ -z "$disk" ]] && { getInput "\nEnter disk\n" disk; [[ -z "$disk" ]] && exitWithError "No disk entered -> exit\n"; }
    cfdisk "$disk"
  }
}
validatePartition() { lsblk -o NAME|grep -qw "${1#/dev/}"||{ exitWithError "$1: Partition does not exist!"; }; }
checkPartitions() { [[ -z "$boot" ]] && getInput "Enter boot partition: " boot; [[ -z "$swap" ]] && getInput "Enter swap partition: " swap; [[ -z "$root" ]] && getInput "Enter root partition: " root; }
validateUser() { [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]] || exitWithError "Invalid username!"; }
checkDebugFlag() { debugstring=$([[ "$debug" =~ ^[yY]$ ]] && echo "" || echo " &>/dev/null"); }
runCMDS() { local s=$1 m=$2 msg=$3 cur=$4 fin=$5 max=$6; shift 6
  [[ "$debug" =~ ^[nN]$ ]] && { ((cur>0)) && printf "${CLEAR}${UP}"; printf "["; for((i=0;i<cur;i++));do printf "#";done; for((i=cur;i<max;i++));do printf " ";done; printf "]\n$m ${WHITE}$msg${NC}"; }
  for c in "$@";do log "$c"; $([ "$s" = 1 ] && echo sudo) bash -c "$c" || exitWithError "Command failed: $c"; done
  [[ "$debug" =~ ^[nN]$ ]] && { printf "${UP}\r["; for((i=0;i<fin;i++));do printf "#";done; for((i=fin;i<max;i++));do printf " ";done; printf "]\n"; }
}
safeCMD() { [[ $1 =~ ^(rm|mv)$ ]]&&{ [[ -e $2 ]]&&"$@"||{ myPrint print yellow "Warning: $2 doesnt exist, skipping $1."; log "Warning: $2 doesnt exist, skipping $1."; }; }||{ "$@"||{ myPrint print red "Error: $* failed."; log "Error: $* failed."; exitWithError "$1 fehlgeschlagen für ${*:2}"; }; }; }
dryRun() { $dryRun&&{ echo "[DRY RUN]: $*"; log "[DRY RUN]: $*"; }||eval "$@"; }
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$logFile"; }
addToBashrc() { grep -qxF "$1" ~/.bashrc || echo "$1" >> ~/.bashrc; }
installBaseSystem() { Banner; checkDebugFlag; runCFDiskIfNeeded; checkPartitions
  for p in boot swap root; do validatePartition ${!p}; myPrint print green "\n${p^} partition: "; printf "${WHITE}${!p}${NC}"; done
  myPrint print red "\n\n!!ATTENTION!!\nThese partitions will be WIPED AND FORMATTED without another Warning!! Please check them TWICE before you continue!!\n!!ATTENTION!!\n\n"
  getInput "Type YES to continue (STRG+C to exit now)..." check "N"; [[ "$check" != "YES" ]] && exitWithError "Formatting was not confirmed!" || printf "\n"
  myPrint countdown 3 "Starting installation in"; printf "\n"
  [[ "$debug" =~ ^[nN]$ ]] && myPrint step Installing "Base system..."
    dryRun runCMDS 0 Formatting drives... 0 7 20 "mkfs.fat -F 32 ${boot} $debugstring" "mkswap ${swap} $debugstring" "swapon ${swap} $debugstring" "mkfs.ext4 -F ${root} $debugstring"
    dryRun runCMDS 0 Mounting partitions... 7 8 20 "mount --mkdir ${root} /mnt $debugstring" "mount --mkdir ${boot} /mnt/boot $debugstring" 
    dryRun runCMDS 0 "Setting up" pacman... 8 13 20 "pacman -Syy $debugstring" "reflector --sort rate --latest 20 --protocol https --country Germany --save /etc/pacman.d/mirrorlist $debugstring" "sed -i '/ParallelDownloads/s/^#//' /etc/pacman.conf"
    dryRun runCMDS 0 Running pacstrap... 13 20 20 "pacstrap -K /mnt base base-devel ${kernel} linux-firmware ${cpu} efibootmgr grub sudo $debugstring" "genfstab -U /mnt >> /mnt/etc/fstab" "cp ./${scriptname} /mnt"
  [[ "$debug" =~ ^[nN]$ ]] && myPrint step ok
  arch-chroot /mnt ./${scriptname} installArchCHRoot
  umount -R /mnt $debugstring; printf "\n"; myPrint countdown 3 "Installation complete! Reboot in"; reboot
}
installArchCHRoot() { checkDebugFlag
  [[ "$debug" =~ ^[nN]$ ]] && myPrint step Configuring "arch-chroot..."
    dryRun runCMDS 0 Setting localtime... 0 7 20 "ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime $debugstring" "hwclock --systohc $debugstring"
    dryRun runCMDS 0 "Setting up" locales... 7 14 20 "sed -e '/${locale}/s/^#*//' -i /etc/locale.gen" "locale-gen $debugstring" "echo LANG=${locale} >> /etc/locale.conf" "echo KEYMAP=${keymap} >> /etc/vconsole.conf"
    dryRun runCMDS 0 "Setting up" GRUB... 14 20 20 "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB $debugstring" "grub-mkconfig -o /boot/grub/grub.cfg $debugstring"
  [[ "$debug" =~ ^[nN]$ ]] && myPrint step ok
  [[ -z "$hostname" ]] && getInput "\nEnter your Hostname: " hostname "SchnuBbyLinux"; echo ${hostname} >> /etc/hostname
  myPrint print yellow "\nEnter your NEW root password\n\n"; myPasswd root
  [[ -z "$user" ]] && getInput "\nEnter your normal username: " user "schnubby"; useradd -mG wheel ${user}
  myPrint print yellow "\nEnter your normal user password\n\n"; myPasswd "${user}"
  sed -e "/%wheel ALL=(ALL:ALL) ALL/s/^#*//" -i /etc/sudoers
  safeCMD mv ./${scriptname} /home/${user}/; addToBashrc "./${scriptname} installDE"
}
installDE() { checkDebugFlag
  [[ -z "$user" ]] && getInput "Enter your normal username: " user "schnubby"
  Banner
  sudo sed -i "/\[multilib\]/,/Include/s/^#//" /etc/pacman.conf
  sudo pacman -Syy $debugstring
  myPrint countdown 3 "Starting installation in"
  [[ "$debug" =~ ^[nN]$ ]] && myPrint step Installing Dependencies...
    dryRun runCMDS 0 Installing "System dependencies..." 0 5 20 "sudo pacman --noconfirm -S --needed hyprland xdg-desktop-portal-{hyprland,gtk} sddm swww polkit-gnome xdg-user-dirs networkmanager $debugstring"
    dryRun runCMDS 0 Installing "Audio dependencies..." 5 10 20 "sudo pacman --noconfirm -S --needed pipewire{,-alsa,-audio,-pulse} gst-plugin-pipewire wireplumber pavucontrol pamixer $debugstring"
    dryRun runCMDS 0 Installing "Additional programs..." 10 19 20 "sudo pacman --noconfirm -S --needed firefox kitty dolphin ark unzip neovim fzf zsh lutris steam teamspeak3 lazygit git $debugstring"
    dryRun runCMDS 0 Installing Fonts... 19 20 20 "sudo pacman --noconfirm -S --needed ttf-jetbrains-mono-nerd $debugstring"
  [[ "$debug" =~ ^[nN]$ ]] && myPrint step ok
  safeCMD git clone https://aur.archlinux.org/yay.git $debugstring; cd yay; safeCMD makepkg -si; cd ..; safeCMD rm ./yay; printf "\n"
  [[ "$debug" =~ ^[nN]$ ]] && myPrint step Running "Post install..."
    dryRun runCMDS 1 Creating "SDDM config directory..." 0 2 20 "sudo mkdir /etc/sddm.conf.d"
    dryRun runCMDS 0 Installing Quickshell... 2 15 20 "yay -S quickshell --noconfirm $debugstring"
    dryRun runCMDS 0 Installing "Custom configs..." 15 17 20 "git clone --depth 1 https://github.com/SchnuBby2205/HyprlandConfigs.git $HOME/.config/hypr/schnubby $debugstring"
    dryRun runCMDS 0 Installing myShell... 17 20 20 "git clone --depth 1 https://github.com/SchnuBby2205/myShell.git $HOME/.config/quickshell/myShell $debugstring"
  [[ "$debug" =~ ^[nN]$ ]] && myPrint step ok && myPrint step Starting Services...
    dryRun runCMDS 0 Starting "Greeter (SDDM)..." 0 7 20 "sudo systemctl enable sddm.service $debugstring"
    dryRun runCMDS 0 Starting "swww-daemon..." 7 15 20 "echo -e 'exec-once=swww-daemon' >> $HOME/.config/hypr/schnubby/userprefs.conf"
    dryRun runCMDS 0 Starting myShell... 15 20 20 "echo -e 'exec-once=quickshell --path $HOME/.config/quickshell/myShell/shell.qml' >> $HOME/.config/hypr/schnubby/userprefs.conf" 
  [[ "$debug" =~ ^[nN]$ ]] && myPrint step ok
  sed -i "/${scriptname}/d" $HOME/.bashrc; echo exec-once=kitty ./${scriptname} installConfigs >> $HOME/.config/hypr/schnubby/userprefs.conf
  myPrint countdown 3 "Reboot in"; reboot
}
installConfigs() { checkDebugFlag; Banner
  [[ -z "$user" ]] && getInput "Enter your normal username: " user "schnubby"
  [[ -z "$gpu" ]] && getInput "Enter your GPU (amd or nvidia): " gpu "amd"
  sudo pacman -Syy $debugstring
  [[ "$debug" =~ ^[nN]$ ]] && myPrint step Running "Final steps..."
    case $gpu in
      amd) dryRun runCMDS 0 Installing "AMD drivers..." 0 5 20 "sudo pacman --noconfirm -S --needed mesa{,-utils} lib32{-mesa,-vulkan-radeon,-vulkan-icd-loader} vulkan{-radeon,-icd-loader} libva{-mesa-driver,-utils} $debugstring";;
      nvidia) dryRun runCMDS 0 Installing "NVIDIA drivers..." 0 5 20 "sudo pacman --noconfirm -S --needed nvidia{-dkms,-utils,-settings} lib32{-nvidia-utils, -vulkan-icd-loader} vulkan-icd-loader $debugstring";;
      *) exitWithError "No valid GPU specified!";;
    esac
      dryRun runCMDS 0 Installing "dxvk-bin..." 5 10 20 "yay -S --noconfirm dxvk-bin $debugstring"
      dryRun runCMDS 0 Installing STEAM... 10 19 20 "steam $debugstring"
      dryRun runCMDS 0 Configuring Hyprland... 19 20 20 "mv $HOME/.config/hypr/hyprland.conf $HOME/.config/hypr/hyprland.bak" "mv $HOME/.config/hypr/schnubby/hyprland.conf $HOME/.config/hypr/" "rm -rf $HOME/.config/hypr/hyprland.bak" # HIER CONFIGS VERTEILEN LAZYVIM, KITTY, WINDOWRULES ETC...!!
    [[ "$debug" =~ ^[nN]$ ]] && myPrint step ok
    #sudo rm -rf $HOME/${scriptname}
    safeCMD rm $HOME/${scriptname}
    sed -i "/${scriptname}/d" $HOME/.config/hypr/schnubby/userprefs.conf
    firefox --ProfileManager
    [[ -z "$defaults" ]] && getInput "\nLoad SchnuBby specific configs (git, lutris, fstab) (y/n)?\n" schnubby "Y"
    [[ "$schnubby" =~ ^[yY]$ || -n "$defaults" ]] && installSchnuBby
    myPrint print green "Installation finished! System will reboot...\n\n"
    myPrint countdown 3 "Reboot in"; reboot
}
installSchnuBby() { checkDebugFlag; [[ "$debug" =~ ^[nN]$ ]] && myPrint step Installing "SchnuBby specifics..."; sudo mount --mkdir /dev/nvme0n1p4 /programmieren $debugstring; for s in fstab autologin lutris zshhist gitconfig gitcred teamspeak3 grub firefox; do case $s in
  fstab) dryRun runCMDS 1 Configuring fstab... 0 2 20 "sudo echo -e '/dev/nvme0n1p4      	/programmieren     	ext4      	rw,relatime	0 1' >> /etc/fstab" "sudo echo -e '/dev/nvme0n1p6      	/spiele     	ext4      	rw,relatime	0 1' >> /etc/fstab";;
  autologin) dryRun runCMDS 1 Setting autologin... 2 5 20 "sudo echo -e '\n[Autologin]\nRelogin=false\nSession=hyprland\nUser=${user}' >> /etc/sddm.conf.d/autologin.conf";;
  lutris) [[ -d "$HOME/.local/share/lutris" ]] && dryRun runCMDS 0 Backing lutris... 5 6 20 "mv $HOME/.local/share/lutris $HOME/.local/share/lutris_bak"; [[ ! -d "$HOME/.local/share/lutris" ]] && runCMDS 0 Configuring lutris... 6 7 20 "ln -s /programmieren/backups/.local/share/lutris $HOME/.local/share/lutris";;
  zshhist) [[ -f "$HOME/.zsh_history" ]] && dryRun runCMDS 0 Removing .zsh_history... 7 8 20 "rm -rf $HOME/.zsh_history"; runCMDS 0 Configuring .zsh_history... 7 9 20 "ln -sf /programmieren/backups/.zsh_history $HOME/.zsh_history";;
  gitconf) [[ ! -f "$HOME/.gitconfig" ]] && dryRun runCMDS 0 Configuring git... 9 11 20 "ln -sf /programmieren/backups/.gitconfig $HOME/.gitconfig";;
  gitcred) [[ ! -f "$HOME/.git-credentials" ]] && dryRun runCMDS 0 Configuring git credentials... 11 13 20 "ln -sf /programmieren/backups/.git-credentials $HOME/.git-credentials";;
  teamspeak3) [[ -f "$HOME/.ts3client" ]] && dryRun runCMDS 0 Removing .ts3client... 13 14 20 "rm -rf $HOME/.ts3client"; runCMDS 0 Configuring .ts3client... 14 15 20 "ln -sf /programmieren/backups/.ts3client $HOME/.ts3client";;
  grub) sudo sed -i "s/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/g" /etc/default/grub; runCMDS 1 Regenerating GRUB... 15 20 20 "sudo grub-mkconfig -o /boot/grub/grub.cfg $debugstring";;
  firefox) ff=$HOME/.mozilla/firefox/$(ls $HOME/.mozilla/firefox | grep "Default User"); rm -rf "$ff"; ln -sf /programmieren/backups/FireFox/3665cjzf.default-release "$ff";;
  *) exitWithError "Error setting SchnuBby secifics!";;
  esac; done; [[ "$debug" =~ ^[nN]$ ]] && myPrint step ok;
}
sudo -v || exitWithError "You need sudo rights for this script."
debug="n"
dryRun=true
boot="/dev/vda1" swap="/dev/vda2" root="/dev/vda3"
hostname="SchnuBbyLinux" user="schnubby"
cpu="intel-ucode" gpu="amd"  
timezone="Europe/Berlin" locale="de_DE.UTF-8" keymap="de-latin1"
kernel="linux-lts"
[[ -z "$1" ]] && installBaseSystem || "$1"
