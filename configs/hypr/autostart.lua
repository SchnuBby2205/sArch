-- Autostarts
hl.on("hyprland.start", function () 
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("~/.config/sArch/bin/sarch_shell.sh")
end)
