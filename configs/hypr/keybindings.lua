-- Variables must be required
require("variables")

-----------------
-- Keybindings --
-----------------

-- Launching and closing
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())

-- Move focus
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Switching and moving windows to Workspaces
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
    hl.bind(mainMod .. " + CTRL + " .. key, function() hl.dispatch(hl.dsp.exec_cmd("hyprctl dispatch movetoworkspacesilent " .. i)) end)
end

-- Cycle through Workspaces with Mousewheel
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Drag and resize Windows
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind(mainMod .. " + mouse:274", hl.dsp.window.fullscreen(), { mouse = true })

-- Starting programs
hl.bind(mainMod .. " + Backspace", hl.dsp.exec_cmd("~/.config/sArch/bin/sarch_powermenu.sh"))
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("kitty btop"))
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(explorer))
hl.bind(mainMod .. " + CTRL + T", hl.dsp.exec_cmd("teamspeak3"), { workspace = 2 })
hl.bind(mainMod .. " + CTRL + S", hl.dsp.exec_cmd("steam"), { workspace = 3 })
hl.bind(mainMod .. " + CTRL + B", hl.dsp.exec_cmd("lutris lutris:rungameid/1"), { workspace = 3 })
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("rofi -show drun -theme ~/.config/rofi/launcher.rasi"))
hl.bind(mainMod .. " + ALT + S", hl.dsp.exec_cmd("~/.config/sArch/bin/sarch_settings.sh"))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("~/.config/sArch/bin/sarch_change_wallpaper.sh"))
hl.bind("F12", hl.dsp.exec_cmd("~/.config/sArch/bin/sarch_change_volume.sh 5%+ unmute"), { repeating = true, locked = true })
hl.bind("F11", hl.dsp.exec_cmd("~/.config/sArch/bin/sarch_change_volume.sh 5%- unmute"), { repeating = true, locked = true })
hl.bind("F10", hl.dsp.exec_cmd("~/.config/sArch/bin/sarch_change_volume.sh toggle"), { repeating = true, locked = true })
hl.bind("F9", hl.dsp.exec_cmd("pavucontrol"), { repeating = true, locked = true })