-- Layer Rules (Match über den Namespace der Layer-Fläche – "class"/"title" gibt es bei Layern nicht,
-- eine Regel damit greift sonst für ALLE Layer, z. B. Blur hinter Bar und Benachrichtigungen)
hl.layer_rule({ name = "Blur for rofi", match = { namespace = "^(rofi)$" }, blur = true })