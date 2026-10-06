-- Layer Rules
hl.layer_rule({ name = "Blur for rofi", match = { class = "^(rofi)$" }, blur = true })
hl.layer_rule({
    name = "neru-no-blur",
    match = { class = "^neru" },   -- ggf. an den echten Namespace anpassen
    blur = false,
})