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
            gaps_out = 5,
            border_size = 2,
            col = {
                active_border = { colors = {primary}, angle = 45 },
                inactive_border = secondary
            },
            resize_on_border = false,
            allow_tearing = false,
            --layout = "dwindle"
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
        },
        input = {
            kb_layout = "de",
            kb_variant = "",
            kb_model = "",
            kb_options = "",
            kb_rules = "",
            follow_mouse = 1,
            sensitivity = 0,
            accel_profile = "flat",
            touchpad = {
                natural_scroll = false
            }
        }
    }
)