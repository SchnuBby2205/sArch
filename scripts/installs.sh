## All Functions that install the system and configure it (the functions are chained together)

installBaseSystem() { Banner; checkDebugFlag; checkUEFI; dmesg -n 1; runCFDiskIfNeeded; checkInstallSettings
  for p in boot swap root; do
    validatePartition ${!p}
    myPrint print green "${p^} partition: "; myPrint print white "${!p}\n"
  done
  myPrint print red "\n!!ATTENTION!!\n\nThese partitions will be\n\nWIPED AND FORMATTED\n\nwithout another Warning!!\nPlease check them TWICE before you continue!!\n\n!!ATTENTION!!\n\n"
  getInput "Type YES to continue (STRG+C to exit now)..." check "N"; [[ "$check" != "YES" ]] && exitWithError "Formatting was not confirmed!" || printf "\n"
  myPrint countdown 3 "Starting installation in"; Banner
  [[ "$debug" == false ]] && myPrint step Installing "Base system..."
    dryRun runCMDS 0 Formatting drives... 0 7 20 "mkfs.fat -F 32 ${boot} $debugstring" "mkswap ${swap} $debugstring" "swapon ${swap} $debugstring" "mkfs.ext4 -F ${root} $debugstring"
    dryRun runCMDS 0 Mounting partitions... 7 8 20 "mount -t ext4 --mkdir ${root} /mnt $debugstring" "mount -t vfat --mkdir ${boot} /mnt/boot $debugstring"
    dryRun runCMDS 0 "Setting up" pacman... 8 13 20 "pacman -Syy $debugstring" "reflector --sort rate --latest 20 --protocol https --country Germany --save /etc/pacman.d/mirrorlist $debugstring" "sed -i '/ParallelDownloads/s/^#//' /etc/pacman.conf"
    dryRun runCMDS 0 Running pacstrap... 13 20 20 "pacstrap -K /mnt base base-devel ${kernel} linux-firmware ${cpu} efibootmgr grub sudo networkmanager terminus-font $debugstring" "genfstab -U /mnt > /mnt/etc/fstab"
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
    dryRun runCMDS 0 "Setting up" locales... 7 14 20 "sed -e '/${locale}/s/^#*//' -i /etc/locale.gen" "locale-gen $debugstring" "echo LANG=${locale} > /etc/locale.conf" "echo KEYMAP=${keymap} > /etc/vconsole.conf" "[[ -n '${consoleFont}' ]] && echo FONT=${consoleFont} >> /etc/vconsole.conf || true"
    dryRun runCMDS 0 "Setting up" GRUB... 14 20 20 "grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB $debugstring" "grub-mkconfig -o /boot/grub/grub.cfg $debugstring"
  [[ "$debug" == false ]] && myPrint step ok
  echo "${hostname}" > /etc/hostname
  useradd -mG wheel ${user}
  sed -e "/%wheel ALL=(ALL:ALL) ALL/s/^#*//" -i /etc/sudoers
  # Passwörter werden erst ganz am Ende (installConfigs) gesetzt. Bis dahin:
  # - sudo ohne Passwort (für pacman, makepkg, yay)
  # - Autologin auf tty1 (startet installDE über den .bashrc-Hook)
  enableInstallMode
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
addFirstbootAutostart() { # $1 = Stufe von install.sh (Standard: installConfigs)
  local stage="${1:-installConfigs}"
  local cfg="$HOME/.config/hypr/hyprland.lua"
  [[ -f "$cfg" ]] || { myPrint print red "Hyprland-Config $cfg nicht gefunden - Autostart nicht gesetzt!\n"; return 1; }
  grep -q 'sARCH-FIRSTBOOT-BEGIN' "$cfg" && return 0
  cat >> "$cfg" <<EOF

-- sARCH-FIRSTBOOT-BEGIN
hl.window_rule({ name = "sArch installer fullscreen", match = { class = "^sarch-installer\$" }, fullscreen = true, opacity = "1.0 1.0" })
hl.on("hyprland.start", function()
  hl.exec_cmd("kitty --class sarch-installer bash -c 'cd \$HOME/sArch && ./install.sh ${stage}'")
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
    for r in systemdeps audiodeps programs programs_extra fonts; do
      readList "$sARCH_INSTALLCONFIGS/$r"
      install="${list[*]}"
      dryRun runCMDS 0 Installing "$name" $s $value 20 "$pacmanRun $install $debugstring"
      s=$value
    done
  [[ "$debug" == false ]] && myPrint step ok
  # yay bauen - Ausgabe von git/makepkg landet im Log, nicht auf dem Bildschirm
  local yayDir="$HOME/.cache/sarch-yay"
  [[ "$debug" == false ]] && myPrint step Installing "yay..."
    dryRun runCMDS 0 Cloning yay... 0 4 20 "rm -rf '$yayDir'" "git clone https://aur.archlinux.org/yay.git '$yayDir' $debugstring"
    dryRun runCMDS 0 Building yay... 4 20 20 "cd '$yayDir' && makepkg -si --noconfirm $debugstring" "rm -rf '$yayDir'"
  [[ "$debug" == false ]] && myPrint step ok
  Banner
  [[ "$debug" == false ]] && myPrint step Running "Post install..."
    runCMDS 1 Creating "SDDM config directory..." 0 1 20 "mkdir -p /etc/sddm.conf.d"
    runCMDS 0 Installing pywalfox... 2 3 20 "$yayRun python-pywalfox $debugstring"
    runCMDS 0 Installing grimblast... 3 4 20 "$yayRun grimblast $debugstring"
    runCMDS 0 Downloading Wallpapers... 4 15 20 "git clone --depth 1 https://github.com/SchnuBby2205/wallpaper.git $HOME/Bilder/Wallpapers $debugstring"
  [[ "$debug" == false ]] && myPrint step ok && myPrint step Creating Theme...
#   runCMDS 0 Copying configs... 0 3 20 'mkdir -p "$HOME/.config"' 'find "$HOME/sArch/configs/" -maxdepth 1 -mindepth 1 -not -name installConfigs -print0 | xargs -0 mv -t "$HOME/.config/"'
#   runCMDS 0 Copying binaries... 3 6 20 'mkdir -p "$HOME/.config/sArch"' 'mv "$HOME/sArch/bin" "$HOME/.config/sArch"'
    runCMDS 0 Linking configs... 0 3 20 'mkdir -p "$HOME/.config"' 'for d in "$HOME/sArch/configs/"*; do [[ "${d##*/}" == installConfigs ]] && continue; ln -sfnT "$d" "$HOME/.config/${d##*/}"; done'
    runCMDS 0 Linking binaries... 3 6 20 'mkdir -p "$HOME/.config/sArch"' 'ln -sfnT "$HOME/sArch/bin" "$HOME/.config/sArch/bin"'
    runCMDS 0 Installing gtk-themes... 6 10 20 'mkdir -p "$HOME/.themes"' 'mv "$HOME/sArch/themes/Matugen" "$HOME/.themes/"'
    runCMDS 0 Caching "fonts and wallpapers..." 10 20 20 'mkdir -p "$HOME/.local/share/fonts"' 'mv "$HOME/sArch/fonts" "$HOME/.local/share/"' 'fc-cache'
  [[ "$debug" == false ]] && myPrint step ok
  applyQuickshell "${quickshell:-true}" install
  addFirstbootAutostart
  [[ "$debug" == false ]] && myPrint step ok && myPrint step Starting Services...
    runCMDS 0 Starting "Greeter (SDDM)..." 0 10 20 "sudo systemctl enable sddm.service $debugstring"
    runCMDS 0 Starting "Networkmanager..." 10 20 20 "sudo systemctl enable NetworkManager $debugstring"
  [[ "$debug" == false ]] && myPrint step ok
  sed -i "/${scriptname}/d" $HOME/.bashrc
  # ab jetzt übernimmt SDDM: tty1-Autologin entfernen, einmalig Autologin in Hyprland
  sudo rm -f "$_GETTY_AUTOLOGIN"
  printf '[Autologin]\nRelogin=false\nSession=hyprland\nUser=%s\n' "$USER" \
    | sudo tee "$_SDDM_FIRSTBOOT" >/dev/null
  Banner
  myPrint countdown 3 "Reboot in"; reboot
}

# ---------------------------------------------------------------------------
# Quickshell (Bar + Einstellungen) an/aus
# ---------------------------------------------------------------------------
# Schalter zur Laufzeit: ~/.config/sArch/quickshell.disabled
#   vorhanden -> autostart (bin/sarch_shell.sh) startet nichts, Einstellungen = GTK-Maske
#   fehlt     -> Quickshell läuft (Bar + Quickshell-Einstellungen)
_QS_MARKER="$HOME/.config/sArch/quickshell.disabled"
_QS_CONFIG="sarch"

_qsRunning() {
  { command -v qs >/dev/null && qs -c "$_QS_CONFIG" ipc show &>/dev/null; } \
    || pgrep -f "(^|/)[q](s|uickshell) .*-c ${_QS_CONFIG}( |\$)" >/dev/null
}

# applyQuickshell true|false [install]
#   install: im Installer-Ablauf (kein laufendes Hyprland, eigene Stage)
applyQuickshell() {
  local want=$1 mode=${2:-} repo
  repo=$(cd "$sARCH_MAIN" && pwd)
  checkDebugFlag
  if [[ "$want" == true ]]; then
    [[ "$debug" == false ]] && myPrint step Enabling "Quickshell..."
      dryRun runCMDS 0 Installing quickshell... 0 6 20 "$pacmanRun quickshell hyprlock $debugstring"
      dryRun runCMDS 0 Installing "Material Symbols..." 6 12 20 "$yayRun ttf-material-symbols-variable $debugstring" "fc-cache $debugstring"
      # Shell-Ordner verlinken (Neuinstallation: ~/.config/quickshell kommt schon vom Config-Link)
      dryRun runCMDS 0 Linking "Quickshell config..." 12 15 20 "mkdir -p '$HOME/.config/sArch'; if [[ -L '$HOME/.config/quickshell' || ! -e '$HOME/.config/quickshell' ]]; then ln -sfnT '$repo/configs/quickshell' '$HOME/.config/quickshell'; else ln -sfnT '$repo/configs/quickshell/$_QS_CONFIG' '$HOME/.config/quickshell/$_QS_CONFIG'; fi" "rm -f '$_QS_MARKER'"
      if [[ "$mode" != install ]] && pgrep -x Hyprland >/dev/null; then
        dryRun runCMDS 0 Starting quickshell... 15 20 20 "_qs=\$(command -v qs || command -v quickshell); pgrep -f '(^|/)[q](s|uickshell) .*-c $_QS_CONFIG( |\$)' >/dev/null || setsid -f \"\$_qs\" -c $_QS_CONFIG -n -d >/dev/null 2>&1 </dev/null"
      fi
    [[ "$debug" == false ]] && myPrint step ok
  else
    [[ "$debug" == false ]] && myPrint step Disabling "Quickshell..."
      dryRun runCMDS 0 Disabling autostart... 0 10 20 "mkdir -p '$HOME/.config/sArch' && touch '$_QS_MARKER'"
      dryRun runCMDS 0 Stopping quickshell... 10 20 20 "command -v qs >/dev/null && qs kill -c $_QS_CONFIG &>/dev/null; pkill -f '(^|/)[q](s|uickshell) .*-c $_QS_CONFIG( |\$)' || true"
    [[ "$debug" == false ]] && myPrint step ok
  fi
  return 0
}

# Menüpunkt Install -> Quickshell
installQuickshell() {
  local sel state
  if [[ -e "$_QS_MARKER" ]]; then state="deaktiviert"; else state="aktiviert"; fi
  _qsRunning && state+=", läuft" || state+=", läuft nicht"
  Banner
  sel=$(list "Quickshell (Bar + Einstellungen) – aktuell: $state" "Aktivieren" "Deaktivieren" "Back") || return 1
  case "$sel" in
    0) quickshell=true;  setSetting quickshell true;  applyQuickshell true ;;
    1) quickshell=false; setSetting quickshell false; applyQuickshell false ;;
    *) return 0 ;;
  esac
  Banner
  if [[ "$quickshell" == true ]]; then
    myPrint print green "Quickshell ist aktiviert.\n"
    myPrint print white "Bar + Einstellungen laufen jetzt (SUPER+ALT+S, SUPER+W).\n"
  else
    myPrint print yellow "Quickshell ist deaktiviert.\n"
    myPrint print white "Keine Bar, SUPER+ALT+S öffnet wieder die GTK-Einstellungen.\n"
  fi
  sleep 2
  return 0
}

# ---------------------------------------------------------------------------
# Backup / SchnuBby specifics
# ---------------------------------------------------------------------------
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
  [[ -n "$BACKUP_DEV" && -n "$BACKUP_MNT" && -n "$GAMES_DEV" && -n "$GAMES_MNT" ]] \
    || { myPrint print yellow "Backup-/Games-Variablen nicht gesetzt - übersprungen.\n"; return 0; }

  [[ "$debug" == false ]] && myPrint step Installing "SchnuBby specifics..."
    sudo mkdir -p "$BACKUP_MNT" "$GAMES_MNT" /etc/sddm.conf.d
    addFstabLine "$BACKUP_DEV" "$BACKUP_MNT" ext4 rw,relatime
    addFstabLine "$GAMES_DEV"  "$GAMES_MNT"  ext4 rw,relatime
    printf '[Autologin]\nRelogin=false\nSession=hyprland\nUser=%s\n' "$USER" \
      | sudo tee /etc/sddm.conf.d/autologin.conf >/dev/null
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
    sudo grub-mkconfig -o /boot/grub/grub.cfg
  [[ "$debug" == false ]] && myPrint step ok
}

installBackup() {
  [[ -n "$BACKUP_DEV" && -n "$BACKUP_MNT" && -n "$BACKUP_DIR" ]] \
    || { myPrint print yellow "Backup-Variablen nicht gesetzt - übersprungen.\n"; return 0; }

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
    local ff="$_FF_DIR/$_FF_PROFILE"
    [[ -e "$ff" || -L "$ff" ]] \
      || ff=$(find "$_FF_DIR" -maxdepth 1 -mindepth 1 -type d -name '*Default User*' 2>/dev/null | head -n1)
    if [[ -n "$ff" ]]; then
      rm -rf "$ff"
      ln -sfn "$BACKUP_DIR/FireFox/3665cjzf.default-release" "$ff"
    else
      myPrint print yellow "Firefox-Profil 'Default User' nicht gefunden - übersprungen.\n"
    fi
  [[ "$debug" == false ]] && myPrint step ok
}

# Firefox-Profil "Default User" ohne ProfileManager anlegen (kein Fenster, Installer bleibt im Vollbild).
# Bewusst ohne [Install...]-Abschnitt: Firefox übernimmt beim ersten Start das Profil mit Default=1.
_FF_DIR="$HOME/.mozilla/firefox"
_FF_PROFILE="sarch.default-user"
createFirefoxProfile() {
  [[ -f "$_FF_DIR/profiles.ini" ]] && return 0      # Firefox lief schon -> nichts überschreiben
  mkdir -p "$_FF_DIR/$_FF_PROFILE"
  cat > "$_FF_DIR/profiles.ini" <<EOF
[Profile0]
Name=Default User
IsRelative=1
Path=$_FF_PROFILE
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF
}

installConfigs() { Banner; checkDebugFlag
  bash -c "sudo pacman -Syy $debugstring"
  [[ "$debug" == false ]] && myPrint step Running "Final steps..."
    readList "$sARCH_INSTALLCONFIGS/$gpu"
    install="${list[*]}"
    # nvidia-dkms braucht die Header zum laufenden Kernel, sonst wird kein Modul gebaut
    [[ "$gpu" == nvidia ]] && install+=" ${kernel}-headers"
    dryRun runCMDS 0 Installing "$name" 0 $value 20 "$pacmanRun $install $debugstring"
    dryRun runCMDS 0 Installing "dxvk-bin..." 5 10 20 "$yayRun dxvk-bin $debugstring"
    # Steam wird nicht gestartet (das Update-Fenster würde den Vollbild-Installer verdecken),
    # das Steam-Runtime-Update passiert beim ersten eigenen Start.
    [[ "$debug" == false ]] && drawProgress 12 20 "Creating Firefox profile..."
    [[ "${dryRun:-}" == true ]] || createFirefoxProfile &>>"${logFile:-/dev/null}"
    [[ "$debug" == false ]] && drawProgress 20 20
  [[ "$debug" == false ]] && myPrint step ok

  _askBackupSpecifics

# mv "$HOME/sArch" "$HOME/sArch_finished"

  # Autostart-Block wieder entfernen
  sed -i '/sARCH-FIRSTBOOT-BEGIN/,/sARCH-FIRSTBOOT-END/d' "$HOME/.config/hypr/hyprland.lua" 2>/dev/null
  [[ -n "$scriptname" ]] && grep -rlF "${scriptname}" "$HOME/.config/hypr" 2>/dev/null | xargs -r sed -i "/${scriptname}/d"

  # Ausgabe von magick/matugen ins Log statt unzentriert auf den Bildschirm
  if [[ "$debug" == false ]]; then
    myPrint step Applying "Theme..."
    drawProgress 0 20 "Setting random wallpaper..."
    _applyRandomWallpaper &>>"${logFile:-/dev/null}"
    drawProgress 20 20
    myPrint step ok
  else
    _applyRandomWallpaper
  fi

  # Passwörter erst ganz zum Schluss setzen, danach Install-Modus (NOPASSWD, Autologin) entfernen
  Banner
  myPrint print yellow "Enter your NEW root password\n\n"; myPasswd root
  Banner
  myPrint print yellow "Enter your password for ${USER}\n\n"; myPasswd "$USER"
  disableInstallMode

  Banner
  myPrint print green "Installation finished! System will reboot...\n\n"
  myPrint countdown 3 "Reboot in"; reboot
}

# Abfrage: Backups / SchnuBby specifics (installConfigs und ISO-Ersteinrichtung)
_askBackupSpecifics() {
  local choice=""
  if [[ "${defaults:-false}" != true ]]; then
    Banner
    choice=$(list "Was soll eingerichtet werden?" "Backups einspielen" "SchnuBby specifics installieren" "Beides" "Überspringen") || choice=3
    choice=$(( choice + 1 ))
  fi
  case "$choice" in
    1) installBackup ;;
    2) installSpecifics ;;
    3) installSpecifics; installBackup ;;
    *) myPrint print yellow "Übersprungen.\n" ;;
  esac
}

# ---------------------------------------------------------------------------
# Ersteinrichtung nach einer Installation von der sArch-ISO (Calamares)
#   Partitionen, Benutzer, Passwörter, Bootloader, Desktop und Theme hat Calamares
#   schon erledigt. Hier kommt nur noch Optionales, das Internet braucht.
#   Startet einmalig beim ersten Hyprland-Start (Vollbild-kitty), danach wieder per
#   install.sh -> Install -> ISO-Ersteinrichtung.
# ---------------------------------------------------------------------------
_isoKernel() { # Kernel-Paket des laufenden Systems (linux, linux-lts, ...)
  cat /usr/lib/modules/"$(uname -r)"/pkgbase 2>/dev/null || echo "${kernel:-linux}"
}
_hasInternet() { ping -c1 -W3 archlinux.org &>/dev/null || ping -c1 -W3 1.1.1.1 &>/dev/null; }
_removeFirstbootAutostart() {
  sed -i '/sARCH-FIRSTBOOT-BEGIN/,/sARCH-FIRSTBOOT-END/d' "$HOME/.config/hypr/hyprland.lua" 2>/dev/null
}

installISOFirstboot() { Banner; checkDebugFlag
  local c
  # --- Internet (ohne geht nur Theme/Firefox) ---
  while ! _hasInternet; do
    Banner
    myPrint print yellow "Keine Internetverbindung.\n\n"
    c=$(list "Wie weiter?" "Netzwerk einrichten (nmtui)" "Erneut prüfen" "Beim nächsten Start nochmal" "Ohne Internet fortfahren") || c=3
    case "$c" in
      0) nmtui ;;
      1) sleep 2 ;;
      2) clear; exit 0 ;;                       # Autostart bleibt -> nächster Login
      3) break ;;
    esac
  done
  local online=false; _hasInternet && online=true

  if [[ "$online" == true ]]; then
    bash -c "sudo pacman -Syy $debugstring"
    # --- NVIDIA: die ISO bringt nur Mesa (AMD/Intel) mit ---
    if lspci 2>/dev/null | grep -Ei 'vga|3d|display' | grep -qi nvidia; then
      Banner
      c=$(list "NVIDIA-Grafikkarte erkannt - Treiber installieren?" "Ja (nvidia-dkms)" "Nein") || c=1
      if [[ "$c" == 0 ]]; then
        [[ "$debug" == false ]] && myPrint step Installing "NVIDIA..."
          readList "$sARCH_INSTALLCONFIGS/nvidia"
          dryRun runCMDS 0 Installing "$name" 0 20 20 "$pacmanRun ${list[*]} $(_isoKernel)-headers $debugstring"
        [[ "$debug" == false ]] && myPrint step ok
      fi
    fi
    # --- persönliche Programme ---
    Banner
    c=$(list "Zusatzprogramme installieren? (Steam, Lutris, TeamSpeak 3, VS Code, dxvk)" "Ja" "Nein") || c=1
    if [[ "$c" == 0 ]]; then
      [[ "$debug" == false ]] && myPrint step Installing "Extra programs..."
        readList "$sARCH_INSTALLCONFIGS/programs_extra"
        dryRun runCMDS 0 Installing "$name" 0 15 20 "$pacmanRun ${list[*]} $debugstring"
        dryRun runCMDS 0 Installing "dxvk-bin..." 15 20 20 "$yayRun dxvk-bin $debugstring"
      [[ "$debug" == false ]] && myPrint step ok
    fi
  fi

  [[ "${dryRun:-}" == true ]] || createFirefoxProfile &>>"${logFile:-/dev/null}"
  [[ "$online" == true ]] && _askBackupSpecifics

  # Theme: setzt die ISO-Installation normalerweise schon, sonst hier nachholen
  [[ -s "$HOME/.cache/sArch/current_wallpaper" ]] || _applyRandomWallpaper &>>"${logFile:-/dev/null}"

  _removeFirstbootAutostart
  Banner
  myPrint print green "Ersteinrichtung abgeschlossen!\n\n"
  c=$(list "Jetzt neu starten?" "Ja" "Nein, weiterarbeiten") || c=1
  [[ "$c" == 0 ]] && reboot
  clear
}

# Zufälliges Wallpaper + Matugen-Farben (rofi liest ~/.cache/Wallpaper_thumbs/curr(_wide),
# das erzeugt sonst nur die Settings-App (Seite Hintergrund), deshalb hier beim ersten Setzen mit anlegen)
_applyRandomWallpaper() {
  local thumbDir="$HOME/.cache/Wallpaper_thumbs/" wp
  wp=$(find "$HOME/Bilder/Wallpapers/" -type f \( -iname '*.jpg' -o -iname '*.png' \) | shuf -n 1)
  sed -i "s|/home/schnubby/|$HOME/|g" "$HOME/.config/matugen/templates/rofi-colors.rasi" "$HOME/.config/rofi/colors.rasi" 2>/dev/null
  [[ -n "$wp" ]] || return 0
  mkdir -p "$thumbDir"
  magick "$wp" -thumbnail 500x500^ -gravity center -extent 500x500 -quality 70 "${thumbDir}curr"
  magick "$wp" -thumbnail 1000x500^ -gravity center -extent 1000x500 -quality 70 "${thumbDir}curr_wide"
  matugen image "$wp"
  # merkt sich die Settings-App als aktuelles Hintergrundbild (Pfad, Farb-Index)
  mkdir -p "$HOME/.cache/sArch" && printf '%s\n0\n' "$wp" > "$HOME/.cache/sArch/current_wallpaper"
}

# ---------------------------------------------------------------------------
# Install-Modus: unbeaufsichtigter Durchlauf bis zum Ende von installConfigs
# ---------------------------------------------------------------------------
_SUDOERS_INSTALL=/etc/sudoers.d/10-sarch-install
_GETTY_AUTOLOGIN=/etc/systemd/system/getty@tty1.service.d/sarch-autologin.conf
_SDDM_FIRSTBOOT=/etc/sddm.conf.d/zz-sarch-firstboot.conf

# läuft im chroot als root
enableInstallMode() {
  # verifypw=any: sonst fragt "sudo -v" trotzdem, weil die %wheel-Regel kein NOPASSWD hat
  printf 'Defaults:%s verifypw=any\n%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$user" "$user" > "$_SUDOERS_INSTALL"
  chmod 440 "$_SUDOERS_INSTALL"
  visudo -cf "$_SUDOERS_INSTALL" >/dev/null || { rm -f "$_SUDOERS_INSTALL"; exitWithError "sudoers file invalid!"; }
  mkdir -p "${_GETTY_AUTOLOGIN%/*}"
  printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty -o "-p -f -- \\\\u" --noclear --autologin %s %%I $TERM\n' "$user" > "$_GETTY_AUTOLOGIN"
}

# läuft als User am Ende von installConfigs
disableInstallMode() {
  sudo rm -f "$_GETTY_AUTOLOGIN" "$_SDDM_FIRSTBOOT"
  sudo rm -f "$_SUDOERS_INSTALL"   # zuletzt, danach fragt sudo wieder nach dem Passwort
}
