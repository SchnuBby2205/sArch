-- Autostarts
hl.on("hyprland.start", function () 
    hl.exec_cmd("awww-daemon")
    hl.exec_cmd("qs -c sarch -n -d")
end)
