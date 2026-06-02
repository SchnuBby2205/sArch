-----------------------------------
-- colors.lua needs to be loaded --
-----------------------------------
require("colors")

--------------------
-- General Config --
--------------------
hl.config(
    {
        general = {
            gaps_in = 5,
            gaps_out = 20,
            border_size = 2,
            col = {
                active_border = { colors = {primary}, angle = 45 },
                inactive_border = secondary
            },
            resize_on_border = false,
            allow_tearing = false,
            layout = "dwindle"
        },
        dwindle = {
            preserve_split = true
        },
        master = {
            new_status = "master"
        },
        scrolling = {
            fullscreen_on_one_column = true
        },
        misc = {
            force_default_wallpaper = -1,
            disable_hyprland_logo = false
        }
    }
)