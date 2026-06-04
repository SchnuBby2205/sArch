-- Workspace configs
hl.workspace_rule({ workspace = "1", default_name = "Main", monitor = "DP-1", default = true })
-- Testing Scrolling workspace on 2
hl.workspace_rule({ workspace = "2", default_name = "Second", monitor = "DP-1", layout = "scrolling" })
--hl.workspace_rule({ workspace = "2", monitor = "DP-1" })
hl.workspace_rule({ workspace = "3", default_name = "Launcher", monitor = "DP-1" })
hl.workspace_rule({ workspace = "4", default_name = "TV", monitor = "DP-2", default = true })

