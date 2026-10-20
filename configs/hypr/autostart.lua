-- Autostarts
hl.on("hyprland.start", function () 
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("~/.config/sArch/bin/sarch_shell.sh")
    -- frisches System (ISO/Neuinstallation): zuletzt gewähltes Wallpaper setzen, falls awww noch keins hat
    hl.exec_cmd("~/.config/sArch/bin/sarch_wallpaper_restore.sh")
    -- nur auf der Live-ISO: Installer (Calamares) anbieten
    hl.exec_cmd("[ -e /etc/sarch-live ] && sarch-install")
end)
