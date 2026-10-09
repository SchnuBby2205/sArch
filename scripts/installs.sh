## All Functions that install the system and configure it (the functions are chained together)

installBaseSystem() { Banner; checkDebugFlag; checkUEFI; dmesg -n 1; runCFDiskIfNeeded; checkInstallSettings
  for p in boot swap root; do
    validatePartition ${!p}
    myPrint print green "${p^} partition: "; printf "${WHITE}${!p}${NC}\n"
  done
  myPrint print red "\n!!ATTENTION!!\nThese partitions will be WIPED AND FORMATTED without another Warning!! Please check them TWICE before you continue!!\n!!ATTENTION!!\n\n"
  getInput "Type YES to continue (STRG+C to exit now)..." check "N"; [[ "$check" != "YES" ]] && exitWithError "Formatting was not confirmed!" || printf "\n"
  myPrint countdown 3 "Starting installation in"; Banner
  [[ "$debug" == false ]] && myPrint step Installing "Base system..."
    dryRun runCMDS 0 Formatting drives... 0 7 20 "mkfs.fat -F 32 ${boot} $debugstring" "mkswap ${swap} $debugstring" "swapon ${swap} $debugstring" "mkfs.ext4 -F ${root} $debugstring"
    dryRun runCMDS 0 Mounting partitions... 7 8 20 "mount -t ext4 --mkdir ${root} /mnt $debugstring" "mount -t vfat --mkdir ${boot} /mnt/boot $debugstring"
    dryRun runCMDS 0 "Setting up" pacman... 8 13 20 "pacman -Syy $debugstring" "reflector --sort rate --latest 20 --protocol https --country Germany --save /etc/pacman.d/mirrorlist $debugstring" "sed -i '/ParallelDownloads/s/^#//' /etc/pacman.conf"
    dryRun runCMDS 0 Running pacstrap... 13 20 20 "pacstrap -K /mnt base base-devel ${kernel} linux-firmware ${cpu} efibootmgr grub sudo networkmanager $debugstring" "genfstab -U /mnt > /mnt/etc/fstab"
  [[ "$debug" == false ]] && myPrint step ok
  cp -r . /mnt/home/sArch
  arch-chroot /mnt /bin/bash -c "cd /home/sArch && ./install.sh installArchCHRoot"
  #arch-chroot /mnt "/mnt/home/sArch/${scriptname} installArchCHRoot"
  [[ -r "$logFile" ]] && cp "$logFile" /mnt/var/log/sArch-install-base.log
  umount -R /mnt; Banner; myPrint countdown 3 "Installation complete! Reboot in"; reboot
}

installArchCHRoot() { Banner; checkDebugFlag
  [[ "$debug" == false ]] && myPrint step Configuring "arch-chroot..."
    dryRun runCMDS 0 Setting localtime... 0 7 20 "ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime $debugstring" "hwclock --systohc $debugstring"
    dryRun runCMDS 0 "Setting up" locales... 7 14 20 "sed -e '/${locale}/s/^#*//' -i /etc/locale.gen" "locale-gen $debugstring" "echo LANG=${locale} > /etc/locale.conf" "echo KEYMAP=${keymap} > /etc/vconsole.conf"
    dryRun runCMDS 0 "Setting up" GRUB... 14 20 20 "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB $debugstring" "grub-mkconfig -o /boot/grub/grub.cfg $debugstring"
  [[ "$debug" == false ]] && myPrint step ok
  echo "${hostname}" > /etc/hostname
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
  chown -R "$user:$user" /home/$user/sArch
  # nur beim Login auf tty1 fortsetzen - nicht in jedem Terminal, falls installDE abbricht
  echo "[[ \"\$(tty)\" == /dev/tty1 ]] && bash -c 'cd /home/$user/sArch && ./install.sh installDE'" >> "/home/$user/.bashrc"
}

# Autostart für installConfigs in die Lua-Config schreiben (wird am Ende wieder entfernt)
addFirstbootAutostart() {
  local cfg="$HOME/.config/hypr/hyprland.lua"
  [[ -f "$cfg" ]] || { myPrint print red "Hyprland-Config $cfg nicht gefunden - Autostart nicht gesetzt!\n"; return 1; }
  grep -q 'sARCH-FIRSTBOOT-BEGIN' "$cfg" && return 0
  cat >> "$cfg" <<'EOF'

-- sARCH-FIRSTBOOT-BEGIN
hl.on("hyprland.start", function()
  hl.exec_cmd("kitty bash -c 'cd $HOME/sArch && ./install.sh installConfigs'")
end)
-- sARCH-FIRSTBOOT-END
EOF
}

installDE() { Banner; checkDebugFlag
  myPrint countdown 3 "Resuming installation in"
  sudo sed -i "/\[multilib\]/,/Include/s/^#//" /etc/pacman.conf
  bash -c "sudo pacman -Syy $debugstring"
  Banner
  [[ "$debug" == false ]] && myPrint step Installing "Dependencies..."
    s=0
    for r in systemdeps audiodeps programs fonts; do
      readList "$sARCH_INSTALLCONFIGS/$r"
      install="${list[*]}"
      dryRun runCMDS 0 Installing "$name" $s $value 20 "$pacmanRun $install $debugstring"
      s=$value
    done
  [[ "$debug" == false ]] && myPrint step ok
  bash -c "git clone https://aur.archlinux.org/yay.git $debugstring"
  cd yay || exitWithError "yay could not be cloned!"
  makepkg -si
  cd ..
  rm -rf ./yay
  Banner
  [[ "$debug" == false ]] && myPrint step Running "Post install..."
    runCMDS 1 Creating "SDDM config directory..." 0 1 20 "mkdir -p /etc/sddm.conf.d"
    runCMDS 0 Installing pywalfox... 2 3 20 "yay -S python-pywalfox --noconfirm $debugstring"
    runCMDS 0 Installing grimblast... 3 4 20 "yay -S grimblast --noconfirm $debugstring"
    runCMDS 0 Downloading Wallpapers... 4 15 20 "git clone --depth 1 https://github.com/mylinuxforwork/wallpaper.git $HOME/Bilder/Wallpapers $debugstring"
  [[ "$debug" == false ]] && myPrint step ok && myPrint step Creating Theme...
#   runCMDS 0 Copying configs... 0 3 20 'mkdir -p "$HOME/.config"' 'find "$HOME/sArch/configs/" -maxdepth 1 -mindepth 1 -not -name installConfigs -print0 | xargs -0 mv -t "$HOME/.config/"'
#   runCMDS 0 Copying binaries... 3 6 20 'mkdir -p "$HOME/.config/sArch"' 'mv "$HOME/sArch/bin" "$HOME/.config/sArch"'
    runCMDS 0 Linking configs... 0 3 20 'mkdir -p "$HOME/.config"' 'for d in "$HOME/sArch/configs/"*; do [[ "${d##*/}" == installConfigs ]] && continue; ln -sfnT "$d" "$HOME/.config/${d##*/}"; done'
    runCMDS 0 Linking binaries... 3 6 20 'mkdir -p "$HOME/.config/sArch"' 'ln -sfnT "$HOME/sArch/bin" "$HOME/.config/sArch/bin"'
    runCMDS 0 Installing gtk-themes... 6 10 20 'mkdir -p "$HOME/.themes"' 'mv "$HOME/sArch/themes/Matugen" "$HOME/.themes/"'
    runCMDS 0 Caching "fonts and wallpapers..." 10 20 20 'mkdir -p "$HOME/.local/share/fonts"' 'mv "$HOME/sArch/fonts" "$HOME/.local/share/"' 'fc-cache' '"$HOME/.config/sArch/bin/sarch_create_thumbnails.sh"'
  addFirstbootAutostart
  [[ "$debug" == false ]] && myPrint step ok && myPrint step Starting Services...
    runCMDS 0 Starting "Greeter (SDDM)..." 0 10 20 "sudo systemctl enable sddm.service $debugstring"
    runCMDS 0 Starting "Networkmanager..." 10 20 20 "sudo systemctl enable NetworkManager $debugstring"
  [[ "$debug" == false ]] && myPrint step ok
  sed -i "/${scriptname}/d" $HOME/.bashrc
  Banner
  myPrint countdown 3 "Reboot in"; reboot
}

# ---------------------------------------------------------------------------
# Backup / SchnuBby specifics
# ---------------------------------------------------------------------------
BACKUP_DEV="/dev/nvme0n1p4"
BACKUP_MNT="/programmieren"
BACKUP_DIR="$BACKUP_MNT/backups"

# fstab-Zeile per UUID anhängen, wenn der Mountpunkt noch nicht drinsteht
# (UUID statt /dev/nvme0n1pX, da sich Gerätenamen z.B. durch eine zweite NVMe ändern können)
addFstabLine() { # $1 = Gerät, $2 = Mountpunkt, $3 = Dateisystem, $4 = Optionen
  local uuid
  grep -qsE "[[:space:]]$2[[:space:]]" /etc/fstab && return 0
  uuid=$(sudo blkid -s UUID -o value "$1")
  [[ -n "$uuid" ]] || { myPrint print red "Keine UUID für $1 gefunden - $2 nicht in fstab eingetragen!\n"; return 1; }
  printf 'UUID=%s   %s   %s   %s   0 2\n' "$uuid" "$2" "$3" "$4" | sudo tee -a /etc/fstab >/dev/null
}

# Symlink auf Backup setzen; vorhandenes Ziel wird gesichert statt gelöscht
linkBackup() { # $1 = Quelle im Backup, $2 = Linkname
  local src="$1" dst="$2"
  [[ -e "$src" ]] || { myPrint print yellow "Übersprungen (nicht im Backup): $src\n"; return 1; }
  if [[ -e "$dst" || -L "$dst" ]]; then
    [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]] && return 0
    mv "$dst" "${dst}_bak_$(date +%s)"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
}

installSpecifics() {
  [[ "$debug" == false ]] && myPrint step Installing "SchnuBby specifics..."
    sudo mkdir -p /programmieren /spiele /etc/sddm.conf.d
    addFstabLine /dev/nvme0n1p4 /programmieren ext4 rw,relatime
    addFstabLine /dev/nvme0n1p6 /spiele        ext4 rw,relatime
    printf '[Autologin]\nRelogin=false\nSession=hyprland\nUser=%s\n' "$USER" \
      | sudo tee /etc/sddm.conf.d/autologin.conf >/dev/null
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg
  [[ "$debug" == false ]] && myPrint step ok
}

installBackup() {
  [[ "$debug" == false ]] && myPrint step Installing "Backup..."
    sudo mkdir -p "$BACKUP_MNT"
    mountpoint -q "$BACKUP_MNT" || sudo mount "$BACKUP_DEV" "$BACKUP_MNT" \
      || { myPrint print red "Backup-Partition $BACKUP_DEV konnte nicht gemountet werden!\n"; return 1; }

    linkBackup "$BACKUP_DIR/.local/share/lutris" "$HOME/.local/share/lutris"
    linkBackup "$BACKUP_DIR/.zsh_history"        "$HOME/.zsh_history"
    linkBackup "$BACKUP_DIR/.gitconfig"          "$HOME/.gitconfig"
    linkBackup "$BACKUP_DIR/.git-credentials"    "$HOME/.git-credentials"
    linkBackup "$BACKUP_DIR/.ts3client"          "$HOME/.ts3client"

    # Firefox: Profil "Default User" durch Link auf das Backup-Profil ersetzen
    local ff
    ff=$(find "$HOME/.mozilla/firefox" -maxdepth 1 -mindepth 1 -type d -name '*Default User*' 2>/dev/null | head -n1)
    if [[ -n "$ff" ]]; then
      rm -rf "$ff"
      ln -sfn "$BACKUP_DIR/FireFox/3665cjzf.default-release" "$ff"
    else
      myPrint print yellow "Firefox-Profil 'Default User' nicht gefunden - übersprungen.\n"
    fi
  [[ "$debug" == false ]] && myPrint step ok
}

installConfigs() { Banner; checkDebugFlag
  bash -c "sudo pacman -Syy $debugstring"
  [[ "$debug" == false ]] && myPrint step Running "Final steps..."
    readList "$sARCH_INSTALLCONFIGS/$gpu"
    install="${list[*]}"
    # nvidia-dkms braucht die Header zum laufenden Kernel, sonst wird kein Modul gebaut
    [[ "$gpu" == nvidia ]] && install+=" ${kernel}-headers"
    dryRun runCMDS 0 Installing "$name" 0 $value 20 "$pacmanRun $install $debugstring"
    dryRun runCMDS 0 Installing "dxvk-bin..." 5 10 20 "yay -S --noconfirm dxvk-bin $debugstring"
    dryRun runCMDS 0 Installing STEAM... 12 17 20 "steam $debugstring"
  [[ "$debug" == false ]] && myPrint step ok

  firefox --ProfileManager

  # --- Abfrage: Backups / SchnuBby specifics ---
  choice=""
  if [[ "${defaults:-false}" != true ]]; then
    myPrint print yellow "\nWas soll eingerichtet werden?\n"
    printf "  1) Backups einspielen\n  2) SchnuBby specifics installieren\n  3) Beides\n  Enter) Überspringen\n"
    read -rp "Auswahl: " choice
  fi
  case "$choice" in
    1) installBackup ;;
    2) installSpecifics ;;
    3) installSpecifics; installBackup ;;
    *) myPrint print yellow "Übersprungen.\n" ;;
  esac

# mv "$HOME/sArch" "$HOME/sArch_finished"

  # Autostart-Block wieder entfernen
  sed -i '/sARCH-FIRSTBOOT-BEGIN/,/sARCH-FIRSTBOOT-END/d' "$HOME/.config/hypr/hyprland.lua" 2>/dev/null
  [[ -n "$scriptname" ]] && grep -rlF "${scriptname}" "$HOME/.config/hypr" 2>/dev/null | xargs -r sed -i "/${scriptname}/d"

  RANDOM_WP=$(find "$HOME/Bilder/Wallpapers/" -type f \( -iname '*.jpg' -o -iname '*.png' \) | shuf -n 1)
  # rofi-Menüs lesen den Hintergrund aus ~/.cache/Wallpaper_thumbs/curr(_wide) - die Dateien
  # erzeugt sonst nur sarch_change_wallpaper.sh, deshalb hier beim ersten Setzen mit anlegen
  local thumbDir="$HOME/.cache/Wallpaper_thumbs/"
  sed -i "s|/home/schnubby/|$HOME/|g" "$HOME/.config/matugen/templates/rofi-colors.rasi" "$HOME/.config/rofi/colors.rasi" 2>/dev/null
  if [[ -n "$RANDOM_WP" ]]; then
    mkdir -p "$thumbDir"
    magick "$RANDOM_WP" -thumbnail 500x500^ -gravity center -extent 500x500 -quality 70 "${thumbDir}curr"
    magick "$RANDOM_WP" -thumbnail 1000x500^ -gravity center -extent 1000x500 -quality 70 "${thumbDir}curr_wide"
    matugen image "${RANDOM_WP}"
  fi

  myPrint print green "Installation finished! System will reboot...\n\n"
  myPrint countdown 3 "Reboot in"; reboot
}
