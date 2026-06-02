-- Windowrules
hl.config({
    windowrule = {
        "fullscreen 1, match:workspace 4",
        "workspace 1, match:class steam_app_default, match:title Hearthstone",
        "opacity 0.8 0.8, match:class ^(.*)$",
        "float 1, match:class ^org.pulseaudio.pavucontrol$",
        "center 1, match:class ^org.pulseaudio.pavucontrol$",
    },

    layerrule = {
        "blur 1, match:class ^(rofi)$",
    },
})