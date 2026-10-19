-- Autostarts
hl.on("hyprland.start", function () 
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("qs -c sarch-settings -n -d")
end)
