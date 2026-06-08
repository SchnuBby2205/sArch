-----------------
-- Keybindings --
-----------------
require("variables")

-- Launching and closing
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal), { description = "Öffnet das Terminal." })
hl.bind(mainMod .. " + Q", hl.dsp.window.close(), { description = "Schließt das aktuelle Fenster." })

-- Move focus
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }), { description = "Verschiebt den Fensterfokus nach links." })
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }), { description = "Verschiebt den Fensterfokus nach rechts." })
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }), { description = "Verschiebt den Fensterfokus nach oben." })
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }), { description = "Verschiebt den Fensterfokus nach unten." })

-- Switching and moving windows to Workspaces
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }), { description = "Setzt den Fokus auf Workspace" .. i .. "." })
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { description = "Verschiebt ein Fenster und Fokus auf Workspace" .. i .. "." })
    hl.bind(mainMod .. " + ALT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }), { description = "Verschiebt ein Fenster auf Workspace" .. i .. "." })
end

-- Cycle through Workspaces with Mousewheel
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Fokus auf den nächsten Workspace." })
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }), { description = "Fokus auf den vorherigen Workspace." })

-- Drag and resize Windows
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true }, { description = "Verschiebt ein Fenster." })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true }, { description = "Verändert die Größe eines Fensters." })
hl.bind(mainMod .. " + mouse:274", hl.dsp.window.fullscreen(), { mouse = true }, { description = "Fenster Vollbild toggle." })

-- Starting programs
hl.bind(mainMod .. " + Backspace", hl.dsp.exec_cmd("~/.config/sArch/bin/sarch_powermenu.sh"), { description = "Öffnet das Powermenu." })
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("kitty btop"), { description = "Öffnet den Taskmanager (btop)." })
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd("firefox"), { description = "Öffnet den Browser." })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("dolphin"), { description = "Öffnet den Datei Explorer" })
-- muss man per window rule machen
hl.bind(mainMod .. " + CTRL + T", hl.dsp.exec_cmd("teamspeak3"), { description = "Öffnet Teamspeak." })
hl.bind(mainMod .. " + CTRL + S", hl.dsp.exec_cmd("steam"), { description = "Öffnet STEAM." })
hl.bind(mainMod .. " + CTRL + B", hl.dsp.exec_cmd("lutris lutris:rungameid/1"), { description = "Öffnet Ballte.Net." })
--
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("rofi -show drun -theme ~/.config/rofi/launcher.rasi"), { description = "Öffnet den Launcher (ROFI)." })
hl.bind(mainMod .. " + ALT + S", hl.dsp.exec_cmd("~/.config/sArch/bin/sarch_settings.sh"), { description = "Öffnet das Settings Fenster." })
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("~/.config/sArch/bin/sarch_change_wallpaper.sh"), { description = "Öffnet die Hintergrundbild Auswahl." })
hl.bind("F12", hl.dsp.exec_cmd("~/.config/sArch/bin/sarch_change_volume.sh 5%+ unmute"), { repeating = true, locked = true }, { description = "Erhöht die Lautstärke um 5%." })
hl.bind("F11", hl.dsp.exec_cmd("~/.config/sArch/bin/sarch_change_volume.sh 5%- unmute"), { repeating = true, locked = true }, { description = "Verringert die Lautstärke um 5%." })
hl.bind("F10", hl.dsp.exec_cmd("~/.config/sArch/bin/sarch_change_volume.sh toggle"), { repeating = true, locked = true }, { description = "Mute/Unmute." })
hl.bind("F9", hl.dsp.exec_cmd("pavucontrol"), { repeating = true, locked = true }, { description = "Öffnet die Sound Einstellungen." })

-- for scrolling workspace 2
hl.bind(mainMod .. " + ALT + mouse_up", hl.dsp.layout("move +col"), { description = "(Scrolling Layout): Scrollt nach links." })  -- Fenster nach rechts verschieben
hl.bind(mainMod .. " + ALT + mouse_down",  hl.dsp.layout("move -col"), { description = "(Scrolling Layout): Scrollt nach rechts." })  -- Spalte nach links tauschen
