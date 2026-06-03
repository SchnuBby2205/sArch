-- Windowrules
hl.window_rule(
    {
        name = "Fullescreen on workspace 4",
        match = { workspace = "4" },
        fullscreen = true
    }    
)
hl.window_rule(
    {
        name = "Opacity for Windows",
        match = { class = "^(.*)$" },
        opacity = "0.9 0.5"
    }
)
hl.window_rule(
    {
        name = "Center pavucontrol",
        match = { class = "^org.pulseaudio.pavucontrol$" },
        float = true,
        center = true
    }
)
hl.window_rule(
    {
        name = "Hearthstone to Workspace 1",
        match = { class = "steam_app_default", title = "Hearthstone" },
        workspace = "1"
    }
)
hl.layer_rule(
    {
        name = "Blur for rofi",
        match = { class = "^(rofi)$" },
        blur = true
    }
)