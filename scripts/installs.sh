## All Functions that install the system and configure it (the functions are chained together)
installBaseSystem() { Banner; checkDebugFlag; runCFDiskIfNeeded; checkInstallSettings
  for p in boot swap root; do validatePartition ${!p}; myPrint print green "${p^} partition: "; printf "${WHITE}${!p}${NC}\n"; done
  myPrint print red "\n!!ATTENTION!!\nThese partitions will be WIPED AND FORMATTED without another Warning!! Please check them TWICE before you continue!!\n!!ATTENTION!!\n\n"
  getInput "Type YES to continue (STRG+C to exit now)..." check "N"; [[ "$check" != "YES" ]] && exitWithError "Formatting was not confirmed!" || printf "\n"
  myPrint countdown 3 "Starting installation in"; Banner
  [[ "$debug" == false ]] && myPrint step Installing "Base system..."
    dryRun runCMDS 0 Formatting drives... 0 7 20 "mkfs.fat -F 32 ${boot} $debugstring" "mkswap ${swap} $debugstring" "swapon ${swap} $debugstring" "mkfs.ext4 -F ${root} $debugstring"
    dryRun runCMDS 0 Mounting partitions... 7 8 20 "mount --mkdir ${root} /mnt $debugstring" "mount --mkdir ${boot} /mnt/boot $debugstring" 
    dryRun runCMDS 0 "Setting up" pacman... 8 13 20 "pacman -Syy $debugstring" "reflector --sort rate --latest 20 --protocol https --country Germany --save /etc/pacman.d/mirrorlist $debugstring" "sed -i '/ParallelDownloads/s/^#//' /etc/pacman.conf"
    dryRun runCMDS 0 Running pacstrap... 13 20 20 "pacstrap -K /mnt base base-devel ${kernel} linux-firmware ${cpu} efibootmgr grub sudo networkmanager $debugstring" "genfstab -U /mnt >> /mnt/etc/fstab" "cp ./${scriptname} /mnt"
  [[ "$debug" == false ]] && myPrint step ok
  cp -r . /mnt/home/sArch
  arch-chroot /mnt /bin/bash -c "cd /home/sArch && ./install.sh installArchCHRoot"
  #arch-chroot /mnt "/mnt/home/sArch/${scriptname} installArchCHRoot"
  umount -R /mnt; Banner; myPrint countdown 3 "Installation complete! Reboot in"; reboot
}
installArchCHRoot() { Banner; checkDebugFlag
  [[ "$debug" == false ]] && myPrint step Configuring "arch-chroot..."
    dryRun runCMDS 0 Setting localtime... 0 7 20 "ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime $debugstring" "hwclock --systohc $debugstring"
    dryRun runCMDS 0 "Setting up" locales... 7 14 20 "sed -e '/${locale}/s/^#*//' -i /etc/locale.gen" "locale-gen $debugstring" "echo LANG=${locale} >> /etc/locale.conf" "echo KEYMAP=${keymap} >> /etc/vconsole.conf"
    dryRun runCMDS 0 "Setting up" GRUB... 14 20 20 "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB $debugstring" "grub-mkconfig -o /boot/grub/grub.cfg $debugstring"
  [[ "$debug" == false ]] && myPrint step ok
  echo ${hostname} >> /etc/hostname
  Banner
  myPrint print yellow "Enter your NEW root password\n\n"; myPasswd root
  useradd -mG wheel ${user}
  Banner
  myPrint print yellow "Enter your normal user password\n\n"; myPasswd "${user}"
  sed -e "/%wheel ALL=(ALL:ALL) ALL/s/^#*//" -i /etc/sudoers
  #safeCMD mv "/$sARCH_MAIN" "/home/${user}/"
  #addToBashrc "$HOME/sARCH/${scriptname} installDE"
  bash -c "systemctl enable NetworkManager $debugstring"
  cd ..
  mv /home/sArch /home/$user/ 
  echo "bash -c 'cd /home/$user/sArch && ./install.sh installDE'" >> "/home/$user/.bashrc"
}
installDE() { Banner; checkDebugFlag
  sudo sed -i "/\[multilib\]/,/Include/s/^#//" /etc/pacman.conf
  bash -c "sudo pacman -Syy $debugstring"
  myPrint countdown 3 "Starting installation in"
  [[ "$debug" == false ]] && myPrint step Installing "Dependencies..."
    s=0; for r in systemdeps audiodeps programs fonts; do readList "$sARCH_INSTALLCONFIGS/$r"; dryRun runCMDS 0 Installing "$name" $s $value 20 "$pacmanRun ${list[@]} $debugstring"; s=$value; done
  [[ "$debug" == false ]] && myPrint step ok
  safeCMD git clone https://aur.archlinux.org/yay.git $debugstring; cd yay; safeCMD makepkg -si; cd ..; safeCMD rm ./yay; printf "\n"
  [[ "$debug" == false ]] && myPrint step Running "Post install..."
    dryRun runCMDS 1 Creating "SDDM config directory..." 0 2 20 "sudo mkdir /etc/sddm.conf.d"
    dryRun runCMDS 0 Installing Quickshell... 2 15 20 "yay -S quickshell --noconfirm $debugstring"
    dryRun runCMDS 0 Installing myShell... 17 20 20 "safeCMD git clone --depth 1 https://github.com/SchnuBby2205/myShell.git $HOME/.config/quickshell/myShell $debugstring"
  [[ "$debug" == false ]] && myPrint step ok && myPrint step Starting Services...
    dryRun runCMDS 0 Starting "Greeter (SDDM)..." 0 10 20 "sudo systemctl enable sddm.service $debugstring"
    dryRun runCMDS 0 Starting "Networkmanager..." 10 20 20 "sudo systemctl enable NetworkManager $debugstring"
  [[ "$debug" == false ]] && myPrint step ok
  sed -i "/${scriptname}/d" $HOME/.bashrc; echo exec-once=kitty $HOME/$sARCH_MAIN/${scriptname} installConfigs >> $HOME/.config/hypr/hyprland.conf
  myPrint countdown 3 "Reboot in"; reboot
}
installConfigs() { Banner; checkDebugFlag
  sudo pacman -Syy $debugstring
  [[ "$debug" == false ]] && myPrint step Running "Final steps..."
    readList "$sARCH_CONFIGS/$gpu"; dryRun runCMDS 0 Installing $name 0 $value 20 "$pacmanRun ${list[@]} $debugstring"
    dryRun runCMDS 0 Installing "dxvk-bin..." 5 10 20 "yay -S --noconfirm dxvk-bin $debugstring"
    safeCMD mv $HOME/.config/hypr $HOME/.config/hypr_bak; safeCMD mv $HOME/$sARCH_CONFIGS/hypr $HOME/.config/hypr
    dryRun runCMDS 0 Installing STEAM... 12 17 20 "steam $debugstring"
  [[ "$debug" == false ]] && myPrint step ok
  firefox --ProfileManager
  [[ -z "$defaults" ]] && getInput "\nLoad Backup configs (git, lutris, fstab) (y/n)?\n" backup "y"
  [[ "$backup" =~ ^[yY]$ ]] && installBackup
  #safeCMD rm $HOME/$sARCH_MAIN
  safeCMD mv $HOME/$sARCH_MAIN $HOME/${sARCH_MAIN}_finished
  myPrint print green "Installation finished! System will reboot...\n\n"
  myPrint countdown 3 "Reboot in"; reboot
}
installBackup() { Banner; checkDebugFlag; [[ "$debug" == false ]] && myPrint step Installing "Backup..."; sudo mount --mkdir /dev/nvme0n1p4 /programmieren $debugstring; for s in fstab autologin lutris zshhist gitconfig gitcred teamspeak3 grub firefox; do case $s in
  fstab) dryRun runCMDS 1 Configuring fstab... 0 2 20 "sudo echo -e '/dev/nvme0n1p4      	/programmieren     	ext4      	rw,relatime	0 1' >> /etc/fstab" "sudo echo -e '/dev/nvme0n1p6      	/spiele     	ext4      	rw,relatime	0 1' >> /etc/fstab";;
  autologin) dryRun runCMDS 1 Setting autologin... 2 5 20 "sudo echo -e '\n[Autologin]\nRelogin=false\nSession=hyprland\nUser=${user}' >> /etc/sddm.conf.d/autologin.conf";;
  lutris) [[ -d "$HOME/.local/share/lutris" ]] && dryRun runCMDS 0 Backing lutris... 5 6 20 "mv $HOME/.local/share/lutris $HOME/.local/share/lutris_bak"; [[ ! -d "$HOME/.local/share/lutris" ]] && runCMDS 0 Configuring lutris... 6 7 20 "ln -s /programmieren/backups/.local/share/lutris $HOME/.local/share/lutris";;
  zshhist) [[ -f "$HOME/.zsh_history" ]] && dryRun runCMDS 0 Removing .zsh_history... 7 8 20 "rm -rf $HOME/.zsh_history"; runCMDS 0 Configuring .zsh_history... 7 9 20 "ln -sf /programmieren/backups/.zsh_history $HOME/.zsh_history";;
  gitconf) [[ ! -f "$HOME/.gitconfig" ]] && dryRun runCMDS 0 Configuring git... 9 11 20 "ln -sf /programmieren/backups/.gitconfig $HOME/.gitconfig";;
  gitcred) [[ ! -f "$HOME/.git-credentials" ]] && dryRun runCMDS 0 Configuring git credentials... 11 13 20 "ln -sf /programmieren/backups/.git-credentials $HOME/.git-credentials";;
  teamspeak3) [[ -f "$HOME/.ts3client" ]] && dryRun runCMDS 0 Removing .ts3client... 13 14 20 "rm -rf $HOME/.ts3client"; runCMDS 0 Configuring .ts3client... 14 15 20 "ln -sf /programmieren/backups/.ts3client $HOME/.ts3client";;
  grub) sudo sed -i "s/GRUB_TIMEOUT=5/GRUB_TIMEOUT=0/g" /etc/default/grub; runCMDS 1 Regenerating GRUB... 15 20 20 "sudo grub-mkconfig -o /boot/grub/grub.cfg $debugstring";;
  firefox) ff=$HOME/.mozilla/firefox/$(ls $HOME/.mozilla/firefox | grep "Default User"); rm -rf "$ff"; ln -sf /programmieren/backups/FireFox/3665cjzf.default-release "$ff";;
  *) exitWithError "Error installing Backup!";;
  esac; done; [[ "$debug" == false ]] && myPrint step ok;
}
