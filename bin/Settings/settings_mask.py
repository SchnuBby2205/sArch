#!/usr/bin/env python3
"""
settings_mask.py – Libadwaita Settings UI
Features:
  - Kategorien-Navigation (Sidebar links)
  - Feldtypen: slider, dropdown, keybind
  - parent_key für verschachtelte Lua-Werte
  - index_field / index_value für wiederholte Blöcke
  - index_field ohne index_value: alle Vorkommen auto-einlesen
  - Neuen Eintrag per + anlegen (new_template)
  - Matugen Colorscheme + Dark Mode
  - sArch: Hintergrundbild (Thumbnails + Akzentfarbe), Schriften (Dunst/Rofi/kitty),
    mirror_files / on_apply für Werte, die in mehreren Dateien stehen
  - --page <Kategorie|Sektion> öffnet direkt eine Seite (z.B. --page wallpaper)
"""

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Pango", "1.0")
from gi.repository import Gtk, Adw, Gdk, Gio, GLib, Pango
import configparser, os, sys, re, json, copy
import subprocess, shlex, shutil, tempfile, threading


# ── Localisation ─────────────────────────────────────────────────────────────

# Gesamte GUI-unabhängige Logik (INI, Lua-Parser, Wallpaper, Fonts) liegt in
# settings_core.py und wird auch vom Quickshell-Backend (settings_backend.py) genutzt.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import settings_core
globals().update({k: v for k, v in vars(settings_core).items() if not k.startswith("__")})


# ── Matugen ───────────────────────────────────────────────────────────────────

MATUGEN_PATHS = [
    os.path.expanduser("~/.themes/Matugen/gtk-4.0/colors.css"),
    os.path.expanduser("~/.cache/matugen/colors.css"),
    os.path.expanduser("~/.config/matugen/colors.css"),
]

_MATUGEN_PROVIDER = None

def apply_matugen_theme():
    raw = None
    for path in MATUGEN_PATHS:
        if os.path.exists(path):
            try:
                with open(path) as f: raw = f.read()
                break
            except OSError: pass
    if not raw: return False
    hex_colors = re.findall(r'#[0-9a-fA-F]{6}', raw)
    primary = hex_colors[0] if hex_colors else None
    css = raw
    if primary:
        r,g,b = int(primary[1:3],16),int(primary[3:5],16),int(primary[5:7],16)
        hover  = f"#{min(255,int(r*1.15)):02x}{min(255,int(g*1.15)):02x}{min(255,int(b*1.15)):02x}"
        on_col = "#1a1a1a" if (0.299*r+0.587*g+0.114*b)>140 else "#ffffff"
        css += f"""
@define-color mat_primary {primary};
@define-color mat_hover   {hover};
@define-color mat_on      {on_col};
button.suggested-action {{
  background-image:none; background-color:@mat_primary;
  color:@mat_on; box-shadow:none; border:none;
}}
button.suggested-action:hover {{
  background-image:none; background-color:@mat_hover; color:@mat_on;
}}
button.suggested-action:active {{
  background-image:none; background-color:@mat_primary; color:@mat_on;
}}
.navigation-sidebar row:selected   {{ background-color:@mat_primary; color:@mat_on; }}
.navigation-sidebar row:selected * {{ color:@mat_on; }}
"""
    # Provider wiederverwenden, damit erneutes Anwenden (nach Wallpaper-Wechsel) nicht stapelt
    global _MATUGEN_PROVIDER
    if _MATUGEN_PROVIDER is None:
        _MATUGEN_PROVIDER = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), _MATUGEN_PROVIDER, Gtk.STYLE_PROVIDER_PRIORITY_USER)
    _MATUGEN_PROVIDER.load_from_string(css)
    return True



def _is_mono_font(item, *_):
    """Filter für den Terminal-Font-Dialog (Monospace oder typische Nerd-/Code-Namen)."""
    fam = item.get_family() if isinstance(item, Pango.FontFace) else item
    try:
        if fam.is_monospace(): return True
    except Exception:
        pass
    return bool(re.search(r'(?i)(mono|code|nerd|iosevka|courier)', fam.get_name() or ""))


# ── GTK4 / Adwaita App ────────────────────────────────────────────────────────

class SettingsApp(Adw.Application):
    def __init__(self, ini_path: str, lang: str = "", page: str = ""):
        super().__init__(application_id="de.local.settings-mask",
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.ini_path = ini_path
        self.start_page = page
        self.category_pending: dict = {}
        self._all_categories: dict = {}
        settings_core._T = load_i18n(lang)
        self.connect("activate", self.on_activate)

    def on_activate(self, app):
        self._all_categories = load_categories(self.ini_path)
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK)
        apply_matugen_theme()

        win = Adw.ApplicationWindow(application=app)
        win.set_title(t("app_title"))
        win.set_default_size(780, 560)
        self._win = win
        self._toast_overlay = Adw.ToastOverlay()

        split = Adw.NavigationSplitView()
        split.set_min_sidebar_width(180)
        split.set_max_sidebar_width(240)

        # ── Sidebar ───────────────────────────────────────────────────────────
        sidebar_page    = Adw.NavigationPage(title=t("sidebar_title"))
        sidebar_toolbar = Adw.ToolbarView()
        sidebar_toolbar.add_top_bar(Adw.HeaderBar())
        sidebar_scroll  = Gtk.ScrolledWindow()
        sidebar_scroll.set_vexpand(True)
        sidebar_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        self._sidebar_list = Gtk.ListBox()
        self._sidebar_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self._sidebar_list.add_css_class("navigation-sidebar")
        self._sidebar_list.set_margin_top(8)
        self._sidebar_list.set_margin_bottom(8)
        self._sidebar_list.set_margin_start(8)
        self._sidebar_list.set_margin_end(8)
        sidebar_scroll.set_child(self._sidebar_list)
        sidebar_toolbar.set_content(sidebar_scroll)
        sidebar_page.set_child(sidebar_toolbar)
        split.set_sidebar(sidebar_page)

        # ── Content ───────────────────────────────────────────────────────────
        self._content_page    = Adw.NavigationPage(title=t("app_title"))
        self._content_toolbar = Adw.ToolbarView()
        self._content_toolbar.add_top_bar(Adw.HeaderBar())
        self._content_page.set_child(self._content_toolbar)
        split.set_content(self._content_page)

        self._category_widgets: dict = {}
        self._build_all_categories()

        first = self._sidebar_list.get_row_at_index(0)
        if self.start_page:
            # --page: Kategoriename oder INI-Sektion (z.B. "wallpaper")
            want = self.start_page
            for cat, entries in self._all_categories.items():
                if any(e.get("section") == want for e in entries):
                    want = cat; break
            i = 0
            while (r := self._sidebar_list.get_row_at_index(i)):
                if r.get_name().lower() == want.lower():
                    first = r; break
                i += 1
        if first:
            self._sidebar_list.select_row(first)
            self._show_category(first.get_name())
        self._sidebar_list.connect("row-selected",
            lambda lb, r: self._show_category(r.get_name()) if r else None)

        self._toast_overlay.set_child(split)
        win.set_content(self._toast_overlay)
        win.present()

    # ── Alle Kategorien aufbauen ──────────────────────────────────────────────

    def _build_all_categories(self):
        # Sidebar leeren
        while self._sidebar_list.get_row_at_index(0):
            self._sidebar_list.remove(self._sidebar_list.get_row_at_index(0))
        self._category_widgets = {}
        self.category_pending  = {}

        for cat_name, settings in self._all_categories.items():
            self.category_pending[cat_name] = {}
            self._category_widgets[cat_name] = self._build_category_page(cat_name, settings)
            self._add_sidebar_row(cat_name)

    def _add_sidebar_row(self, cat_name: str):
        row     = Gtk.ListBoxRow()
        row_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row_box.set_margin_top(10); row_box.set_margin_bottom(10)
        row_box.set_margin_start(12); row_box.set_margin_end(12)
        row_box.append(Gtk.Image.new_from_icon_name("preferences-system-symbolic"))
        lbl = Gtk.Label(label=cat_name)
        lbl.set_halign(Gtk.Align.START); lbl.set_hexpand(True)
        row_box.append(lbl)
        row.set_child(row_box); row.set_name(cat_name)
        self._sidebar_list.append(row)

    # ── Kategorie-Seite ───────────────────────────────────────────────────────

    def _build_category_page(self, cat_name: str, settings: list) -> Gtk.Widget:
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        clamp = Adw.Clamp()
        clamp.set_maximum_size(660)
        clamp.set_margin_top(16); clamp.set_margin_bottom(16)
        clamp.set_margin_start(16); clamp.set_margin_end(16)
        outer_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20)

        # ── Auto-Index: index_field ohne index_value ──────────────────────────
        # Wir expandieren solche Einträge zu mehreren Gruppen
        expanded = []
        for s in settings:
            if s["index_field"] and not s["index_value"] and s["config_file"]:
                # Alle Vorkommen einlesen
                try:
                    with open(s["config_file"]) as f: lines = f.readlines()
                    all_blocks = _find_all_indexed_blocks(lines, s["index_field"])
                    for (val, _, _) in all_blocks:
                        sc = copy.deepcopy(s)
                        sc["index_value"] = val
                        expanded.append(sc)
                except OSError:
                    expanded.append(s)  # Fallback
            else:
                expanded.append(s)

        # ── Gruppieren nach index_value ───────────────────────────────────────
        groups: dict = {}
        for s in expanded:
            grp = s["index_value"] if s["index_value"] else "__default__"
            groups.setdefault(grp, []).append(s)

        has_new_template = any(s.get("new_template") for s in settings)

        for grp_title, entries in groups.items():
            added = 0
            pref_group = Adw.PreferencesGroup()
            pref_group.set_title(grp_title if grp_title != "__default__" else cat_name)
            pref_group.set_description(t("pref_group_hint"))

            # + Button in Header wenn new_template vorhanden
            if has_new_template and grp_title == list(groups.keys())[0]:
                add_btn = Gtk.Button()
                add_btn.set_icon_name("list-add-symbolic")
                add_btn.add_css_class("flat")
                add_btn.set_tooltip_text(t("tooltip_add"))
                add_btn.connect("clicked", self._on_new_entry, cat_name, settings)
                pref_group.set_header_suffix(add_btn)

            for s in entries:
                if s["type"] in ("variable","animation","autostart","workspace_rule","layer_rule",
                                 "wallpaper","fonts"):
                    self._add_special_group(outer_box, cat_name, s)
                    break
                elif s["type"] == "multisetting":
                    self._add_keybind(pref_group, cat_name, s)
                elif s["type"] == "dropdown":
                    self._add_dropdown(pref_group, cat_name, s)
                else:
                    self._add_slider(pref_group, cat_name, s)
                added += 1

            # Spezial-Seiten bringen eigene Gruppen mit -> keine leere Kopfgruppe anhängen
            if added:
                outer_box.append(pref_group)
                outer_box.append(Gtk.Separator())

        # Buttons (nicht auf Seiten, die sofort anwenden, z.B. Hintergrund)
        if not all(s["type"] == "wallpaper" for s in settings):
            btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            btn_box.set_halign(Gtk.Align.END); btn_box.set_margin_top(4)
            reset_btn = Gtk.Button(label=t("btn_reset"))
            reset_btn.add_css_class("flat")
            reset_btn.connect("clicked", self._on_reset, cat_name)
            apply_btn = Gtk.Button(label=t("btn_apply"))
            apply_btn.add_css_class("suggested-action")
            apply_btn.connect("clicked", self._on_apply, cat_name)
            btn_box.append(reset_btn); btn_box.append(apply_btn)
            outer_box.append(btn_box)

        clamp.set_child(outer_box)
        scroll.set_child(clamp)
        return scroll

    # ── Slider ────────────────────────────────────────────────────────────────

    def _add_special_group(self, outer_box: Gtk.Box, cat_name: str, s: dict):
        """Router für variable, animation, autostart, workspace_rule, layer_rule."""
        t = s["type"]
        if t == "variable":
            self._add_variable_group(outer_box, cat_name, s)
        elif t == "animation":
            self._add_animation_group(outer_box, cat_name, s)
        elif t == "autostart":
            self._add_autostart_group(outer_box, cat_name, s)
        elif t == "workspace_rule":
            self._add_workspace_rule_group(outer_box, cat_name, s)
        elif t == "layer_rule":
            self._add_layer_rule_group(outer_box, cat_name, s)
        elif t == "wallpaper":
            self._add_wallpaper_group(outer_box, cat_name, s)
        elif t == "fonts":
            self._add_fonts_group(outer_box, cat_name, s)

    def _add_variable_group(self, outer_box: Gtk.Box, cat_name: str, s: dict):
        """Zeigt alle Variablen aus der Datei als editierbare Rows."""
        config_file = s["config_file"]
        variables   = read_variables(config_file)

        pref_group = Adw.PreferencesGroup()
        pref_group.set_title(s["label"] or cat_name)
        if s["description"]: pref_group.set_description(s["description"])

        # + Button
        add_btn = Gtk.Button()
        add_btn.set_icon_name("list-add-symbolic")
        add_btn.add_css_class("flat")
        add_btn.set_tooltip_text(t("tooltip_add"))
        add_btn.connect("clicked", self._on_new_variable, cat_name, config_file, outer_box, s)
        pref_group.set_header_suffix(add_btn)

        for var_name, var_value, line_idx in variables:
            row = Adw.ActionRow()
            row.set_title(var_name)
            row.set_activatable(False)

            # Wert-Eingabe
            entry = Gtk.Entry()
            entry.set_text(var_value)
            entry.set_hexpand(True)
            entry.set_valign(Gtk.Align.CENTER)
            entry.set_margin_start(8)
            row.add_suffix(entry)

            # Mülltonne
            del_btn = Gtk.Button()
            del_btn.set_icon_name("user-trash-symbolic")
            del_btn.add_css_class("flat")
            del_btn.add_css_class("destructive-action")
            del_btn.set_valign(Gtk.Align.CENTER)
            del_btn.set_tooltip_text(t("tooltip_delete"))

            def make_del(cfg, lidx, r, cat, ob, sv):
                def cb(_):
                    dialog = Adw.AlertDialog(
                        heading=t("delete_heading"),
                        body=f"Variable \"{r.get_title()}\" wird entfernt.",
                    )
                    dialog.add_response("cancel", t("btn_cancel"))
                    dialog.add_response("delete", t("btn_delete"))
                    dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)
                    dialog.set_default_response("cancel")
                    def on_resp(d, resp):
                        if resp != "delete": return
                        if delete_variable(cfg, lidx):
                            self._rebuild_special_page(cat, ob, sv)
                            toast = Adw.Toast(title=t("toast_var_deleted"))
                            toast.set_timeout(3)
                            self._toast_overlay.add_toast(toast)
                    dialog.connect("response", on_resp)
                    dialog.present(self._win)
                return cb

            del_btn.connect("clicked", make_del(config_file, line_idx, row, cat_name, outer_box, s))
            row.add_suffix(del_btn)
            pref_group.add(row)

            uid = f"variable|{config_file}|{var_name}|{line_idx}"
            self.category_pending[cat_name][uid] = {
                "type": "variable", "entry": entry,
                "config_file": config_file, "var_name": var_name,
                "line_idx": line_idx, "original": var_value,
            }

        outer_box.append(pref_group)

    def _rebuild_special_page(self, cat_name: str, outer_box: Gtk.Box, s: dict):
        """Baut eine special-Seite (variable/animation/autostart/etc.) neu auf."""
        child = outer_box.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            outer_box.remove(child)
            child = nxt
        self.category_pending[cat_name] = {}
        self._add_special_group(outer_box, cat_name, s)
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        btn_box.set_halign(Gtk.Align.END); btn_box.set_margin_top(4)
        reset_btn = Gtk.Button(label=t("btn_reset"))
        reset_btn.add_css_class("flat")
        reset_btn.connect("clicked", self._on_reset, cat_name)
        apply_btn = Gtk.Button(label=t("btn_apply"))
        apply_btn.add_css_class("suggested-action")
        apply_btn.connect("clicked", self._on_apply, cat_name)
        btn_box.append(reset_btn); btn_box.append(apply_btn)
        outer_box.append(btn_box)

    def _rebuild_variable_page(self, cat_name: str, outer_box: Gtk.Box, s: dict):
        """Baut die Variable-Seite neu auf."""
        self._rebuild_special_page(cat_name, outer_box, s)

    # ── Generische Inline-Rule Gruppe ────────────────────────────────────────

    def _add_inline_rule_group(self, outer_box, cat_name, s, reader,
                                writer, appender, index_field,
                                field_defs, title_key="_line"):
        """
        Generische Gruppe für einzeilige Rules (animation, workspace_rule, layer_rule).
        field_defs: [{"key": k, "label": l, "type": "text"|"dropdown", "options": [...]}]
        """
        config_file = s["config_file"]
        entries     = reader(config_file)

        pref_group  = Adw.PreferencesGroup()
        pref_group.set_title(s["label"] or cat_name)
        if s["description"]: pref_group.set_description(s["description"])

        add_btn = Gtk.Button()
        add_btn.set_icon_name("list-add-symbolic")
        add_btn.add_css_class("flat")
        add_btn.set_tooltip_text(t("tooltip_add"))
        add_btn.connect("clicked", self._on_new_inline_rule,
                        cat_name, s, field_defs, appender, outer_box)
        pref_group.set_header_suffix(add_btn)

        for entry in entries:
            line_idx  = entry.get("_line", 0)
            row_title = entry.get(index_field, f"Zeile {line_idx+1}")

            exp_row = Adw.ExpanderRow()
            exp_row.set_title(row_title)
            exp_row.set_activatable(True)

            widgets = {}

            # Felder nach block-Namen gruppieren
            block_groups: dict = {}
            no_block: list     = []
            block_order: list  = []
            for fd in field_defs:
                blk = fd.get("block")
                if blk:
                    if blk not in block_groups:
                        block_groups[blk] = []
                        block_order.append(blk)
                    block_groups[blk].append(fd)
                else:
                    no_block.append(fd)

            def _add_fd(container, fd, fval):
                fk = fd["key"]; fl = fd["label"]
                ftype = fd.get("type","text"); fopts = fd.get("options",[])
                if ftype == "dropdown":
                    eff = list(fopts)
                    if fval and fval not in eff: eff.insert(0, fval)
                    fidx = eff.index(fval) if fval in eff else 0
                    combo = Adw.ComboRow()
                    combo.set_title(fl)
                    combo.set_model(Gtk.StringList.new(eff))
                    combo.set_selected(fidx)
                    container.add_row(combo)
                    widgets[fk] = ("dropdown", combo, eff)
                else:
                    te = Adw.EntryRow(); te.set_title(fl); te.set_text(str(fval))
                    container.add_row(te)
                    widgets[fk] = ("text", te, [])

            for fd in no_block:
                _add_fd(exp_row, fd, entry.get(fd["key"], ""))
            for blk_name in block_order:
                blk_row = Adw.ExpanderRow()
                blk_row.set_title(blk_name); blk_row.set_expanded(True)
                for fd in block_groups[blk_name]:
                    _add_fd(blk_row, fd, entry.get(fd["key"], ""))
                exp_row.add_row(blk_row)

            # Mülltonne
            del_btn = Gtk.Button()
            del_btn.set_icon_name("user-trash-symbolic")
            del_btn.add_css_class("flat")
            del_btn.add_css_class("destructive-action")
            del_btn.set_valign(Gtk.Align.CENTER)
            del_btn.set_tooltip_text(t("tooltip_delete"))

            def make_del(lidx, row, cat, ob, sv):
                def cb(_):
                    dialog = Adw.AlertDialog(
                        heading=t("delete_heading"),
                        body=f"\"{row.get_title()}\" wird dauerhaft entfernt.",
                    )
                    dialog.add_response("cancel", t("btn_cancel"))
                    dialog.add_response("delete", t("btn_delete"))
                    dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)
                    dialog.set_default_response("cancel")
                    def on_resp(d, resp):
                        if resp != "delete": return
                        if delete_line(config_file, lidx):
                            self._rebuild_special_page(cat, ob, sv)
                            toast = Adw.Toast(title=t("toast_entry_deleted"))
                            toast.set_timeout(3)
                            self._toast_overlay.add_toast(toast)
                    dialog.connect("response", on_resp)
                    dialog.present(self._win)
                return cb

            del_btn.connect("clicked", make_del(line_idx, exp_row, cat_name, outer_box, s))
            exp_row.add_suffix(del_btn)
            pref_group.add(exp_row)

            uid = f"{s['type']}|{config_file}|{line_idx}"
            self.category_pending[cat_name][uid] = {
                "type": s["type"], "widgets": widgets,
                "config_file": config_file, "line_idx": line_idx,
                "writer": writer, "field_defs": field_defs,
                "original": dict(entry),
            }

        outer_box.append(pref_group)

    def _on_new_inline_rule(self, _btn, cat_name, s, field_defs, appender, outer_box):
        """Dialog zum Anlegen eines neuen Inline-Rule Eintrags."""
        dialog = Adw.AlertDialog(heading=t("new_entry_heading"), body=t("new_entry_body"))
        box    = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_top(8); box.set_size_request(420, -1)
        fw = {}
        for fd in field_defs:
            lbl = Gtk.Label(label=fd["label"])
            lbl.set_halign(Gtk.Align.START); lbl.add_css_class("dim-label")
            box.append(lbl)
            if fd.get("type") == "dropdown":
                dd = Gtk.DropDown.new_from_strings(fd.get("options",[]))
                dd.set_hexpand(True)
                box.append(dd)
                fw[fd["key"]] = ("dropdown", dd, fd.get("options",[]))
            else:
                e = Gtk.Entry(); e.set_hexpand(True)
                e.set_placeholder_text(fd["label"])
                box.append(e)
                fw[fd["key"]] = ("text", e, [])
        dialog.set_extra_child(box)
        dialog.add_response("cancel", t("btn_cancel"))
        dialog.add_response("create", t("btn_create"))
        dialog.set_default_response("create")
        dialog.set_response_appearance("create", Adw.ResponseAppearance.SUGGESTED)
        def on_resp(d, resp):
            if resp != "create": return
            vals = {}
            for k,(ft,w,opts) in fw.items():
                if ft == "dropdown":
                    idx = w.get_selected()
                    vals[k] = opts[idx] if idx < len(opts) else ""
                else:
                    vals[k] = w.get_text().strip()
            if appender(s["config_file"], vals):
                self._rebuild_special_page(cat_name, outer_box, s)
                toast = Adw.Toast(title=t("toast_entry_created"))
                toast.set_timeout(3)
                self._toast_overlay.add_toast(toast)
        dialog.connect("response", on_resp)
        dialog.present(self._win)

    # ── Animation ─────────────────────────────────────────────────────────────

    def _add_animation_group(self, outer_box, cat_name, s):
        ANIM_FIELDS = [
            {"key":"leaf",    "label":"Leaf (Name)",  "type":"text"},
            {"key":"enabled", "label":"Aktiviert",    "type":"dropdown","options":["true","false"]},
            {"key":"speed",   "label":"Geschwindigkeit","type":"text"},
            {"key":"bezier",  "label":"Bezier",       "type":"text"},
            {"key":"spring",  "label":"Spring",       "type":"text"},
            {"key":"style",   "label":"Style",        "type":"text"},
        ]
        def anim_appender(cfg, vals):
            return append_animation(cfg, vals)
        def anim_writer(cfg, lidx, fields):
            return write_animation(cfg, lidx, fields)
        self._add_inline_rule_group(
            outer_box, cat_name, s,
            reader=read_animations, writer=anim_writer,
            appender=anim_appender, index_field="leaf",
            field_defs=ANIM_FIELDS,
        )

    # ── Autostart ──────────────────────────────────────────────────────────────

    def _add_autostart_group(self, outer_box, cat_name, s):
        """Autostart: einfache Liste von hl.exec_cmd() Einträgen."""
        config_file = s["config_file"]
        entries     = read_autostarts(config_file)

        pref_group = Adw.PreferencesGroup()
        pref_group.set_title(s["label"] or cat_name)
        if s["description"]: pref_group.set_description(s["description"])

        add_btn = Gtk.Button()
        add_btn.set_icon_name("list-add-symbolic")
        add_btn.add_css_class("flat")
        add_btn.connect("clicked", self._on_new_autostart, cat_name, s, outer_box)
        pref_group.set_header_suffix(add_btn)

        for entry in entries:
            line_idx = entry["_line"]
            row = Adw.ActionRow()
            row.set_title(entry["cmd"])
            row.set_activatable(False)

            te = Gtk.Entry()
            te.set_text(entry["cmd"])
            te.set_hexpand(True); te.set_valign(Gtk.Align.CENTER)
            te.set_margin_start(8)
            row.add_suffix(te)

            del_btn = Gtk.Button()
            del_btn.set_icon_name("user-trash-symbolic")
            del_btn.add_css_class("flat"); del_btn.add_css_class("destructive-action")
            del_btn.set_valign(Gtk.Align.CENTER)

            def make_del(lidx, r, cat, ob, sv):
                def cb(_):
                    dialog = Adw.AlertDialog(heading=t("delete_heading"),
                                             body=t("delete_body_autostart"))
                    dialog.add_response("cancel", t("btn_cancel"))
                    dialog.add_response("delete", t("btn_delete"))
                    dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)
                    dialog.set_default_response("cancel")
                    def on_resp(d, resp):
                        if resp != "delete": return
                        if delete_line(config_file, lidx):
                            self._rebuild_special_page(cat, ob, sv)
                            toast = Adw.Toast(title=t("toast_entry_deleted"))
                            toast.set_timeout(3); self._toast_overlay.add_toast(toast)
                    dialog.connect("response", on_resp); dialog.present(self._win)
                return cb

            del_btn.connect("clicked", make_del(line_idx, row, cat_name, outer_box, s))
            row.add_suffix(del_btn)
            pref_group.add(row)

            uid = f"autostart|{config_file}|{line_idx}"
            self.category_pending[cat_name][uid] = {
                "type":"autostart","entry":te,
                "config_file":config_file,"line_idx":line_idx,
                "original":entry["cmd"],
            }

        outer_box.append(pref_group)

    def _on_new_autostart(self, _btn, cat_name, s, outer_box):
        dialog = Adw.AlertDialog(heading=t("new_autostart_heading"),
                                 body=t('new_autostart_body'))
        e = Gtk.Entry(); e.set_placeholder_text(t("new_autostart_value_ph"))
        e.set_margin_top(8); e.set_size_request(360,-1)
        dialog.set_extra_child(e)
        dialog.add_response("cancel", t("btn_cancel"))
        dialog.add_response("create", t("btn_create"))
        dialog.set_default_response("create")
        dialog.set_response_appearance("create", Adw.ResponseAppearance.SUGGESTED)
        def on_resp(d, resp):
            if resp != "create": return
            cmd = e.get_text().strip()
            if not cmd: return
            if append_autostart(s["config_file"], cmd):
                self._rebuild_special_page(cat_name, outer_box, s)
                toast = Adw.Toast(title=t("toast_autostart_created"))
                toast.set_timeout(3); self._toast_overlay.add_toast(toast)
        dialog.connect("response", on_resp); dialog.present(self._win)

    # ── Workspace Rules ────────────────────────────────────────────────────────

    def _add_workspace_rule_group(self, outer_box, cat_name, s):
        WS_FIELDS = [
            {"key":"workspace",    "label":"Workspace",     "type":"text"},
            {"key":"default_name", "label":"Name",          "type":"text"},
            {"key":"monitor",      "label":"Monitor",       "type":"text"},
            {"key":"layout",       "label":"Layout",        "type":"dropdown",
             "options":["","scrolling","dwindle","master"]},
            {"key":"default",      "label":"Standard",      "type":"dropdown",
             "options":["","true","false"]},
        ]
        def ws_appender(cfg, vals):
            clean = {k:v for k,v in vals.items() if v and v != ""}
            return append_workspace_rule(cfg, clean)
        def ws_writer(cfg, lidx, fields):
            clean = {k:v for k,v in fields.items() if v and v != "" and k != "_line"}
            return write_workspace_rule(cfg, lidx, clean)
        self._add_inline_rule_group(
            outer_box, cat_name, s,
            reader=read_workspace_rules, writer=ws_writer,
            appender=ws_appender, index_field="workspace",
            field_defs=WS_FIELDS,
        )

    # ── Layer Rules ───────────────────────────────────────────────────────────

    def _add_layer_rule_group(self, outer_box, cat_name, s):
        LR_FIELDS = [
            {"key":"name",  "label":"Name",          "type":"text"},
            {"key":"class", "label":"Klasse (Regex)","type":"text"},
            {"key":"blur",  "label":"Blur",          "type":"dropdown","options":["","true","false"]},
        ]
        def lr_appender(cfg, vals):
            return append_layer_rule(cfg, vals)
        def lr_writer(cfg, lidx, fields):
            return write_layer_rule(cfg, lidx, fields)
        self._add_inline_rule_group(
            outer_box, cat_name, s,
            reader=read_layer_rules, writer=lr_writer,
            appender=lr_appender, index_field="name",
            field_defs=LR_FIELDS,
        )

    def _on_new_variable(self, _btn, cat_name: str, config_file: str,
                         outer_box: Gtk.Box, s: dict):
        """Dialog zum Anlegen einer neuen Variable."""
        dialog = Adw.AlertDialog(heading=t("new_variable_heading"), body=t("new_variable_body"))
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_top(8); box.set_size_request(360, -1)
        name_entry  = Gtk.Entry(); name_entry.set_placeholder_text(t("new_variable_name_ph"))
        value_entry = Gtk.Entry(); value_entry.set_placeholder_text(t("new_variable_value_ph"))
        lbl_n = Gtk.Label(label=t("name_label")); lbl_n.set_halign(Gtk.Align.START); lbl_n.add_css_class("dim-label")
        lbl_v = Gtk.Label(label=t("value_label")); lbl_v.set_halign(Gtk.Align.START); lbl_v.add_css_class("dim-label")
        box.append(lbl_n); box.append(name_entry)
        box.append(lbl_v); box.append(value_entry)
        dialog.set_extra_child(box)
        dialog.add_response("cancel", t("btn_cancel"))
        dialog.add_response("create", t("btn_create"))
        dialog.set_default_response("create")
        dialog.set_response_appearance("create", Adw.ResponseAppearance.SUGGESTED)
        def on_resp(d, resp):
            if resp != "create": return
            n = name_entry.get_text().strip()
            v = value_entry.get_text().strip()
            if not n or not v: return
            if append_variable(config_file, n, v):
                self._rebuild_variable_page(cat_name, outer_box, s)
                toast = Adw.Toast(title=t("toast_var_created", name=n))
                toast.set_timeout(3)
                self._toast_overlay.add_toast(toast)
        dialog.connect("response", on_resp)
        dialog.present(self._win)

    def _add_slider(self, group, cat_name, s):
        current = read_current_value(s["config_file"], s, s["min"])
        current = max(s["min"], min(s["max"], current))

        row = Adw.ActionRow()
        row.set_title(s["label"])
        if s["description"]: row.set_subtitle(s["description"])
        row.set_activatable(False)
        value_label = Gtk.Label(label=str(int(current)))
        value_label.set_width_chars(3); value_label.set_xalign(1.0)
        value_label.add_css_class("numeric"); value_label.add_css_class("dim-label")
        row.add_suffix(value_label)

        slider_row = Adw.ActionRow(); slider_row.set_activatable(False)
        adj = Gtk.Adjustment(value=current, lower=s["min"], upper=s["max"],
            step_increment=s["step"], page_increment=s["step"]*5)
        scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=adj)
        scale.set_value(current); scale.set_hexpand(True)
        scale.set_draw_value(False); scale.set_digits(0)
        scale.set_margin_start(8); scale.set_margin_end(8)
        scale.set_margin_top(4); scale.set_margin_bottom(4)
        scale.add_mark(s["min"], Gtk.PositionType.BOTTOM, str(int(s["min"])))
        scale.add_mark(s["max"], Gtk.PositionType.BOTTOM, str(int(s["max"])))

        def make_cb(vl, sc):
            def cb(_):
                step = sc.get_adjustment().get_step_increment()
                snapped = round(sc.get_value()/step)*step if step>0 else sc.get_value()
                vl.set_label(str(int(snapped)))
            return cb
        scale.connect("value-changed", make_cb(value_label, scale))
        slider_row.add_prefix(scale)
        group.add(row); group.add(slider_row)

        uid = f"{s['config_key']}|{s['config_file']}|{s.get('index_value','')}|{s.get('parent_key','')}"
        self.category_pending[cat_name][uid] = {
            "type":"slider", "scale":scale,
            "config_file":s["config_file"], "config_key":s["config_key"],
            "parent_key":s["parent_key"], "index_field":s["index_field"],
            "index_value":s["index_value"], "original":current, "format":s["format"],
            "mirror_files":s.get("mirror_files", []), "on_apply":s.get("on_apply", ""),
        }

    # ── Dropdown ──────────────────────────────────────────────────────────────

    def _add_dropdown(self, group, cat_name, s):
        options     = s["options"]
        current_str = read_current_string(s["config_file"], s, options[0] if options else "")
        current_idx = options.index(current_str) if current_str in options else 0

        combo = Adw.ComboRow()
        combo.set_title(s["label"])
        if s["description"]: combo.set_subtitle(s["description"])
        combo.set_model(Gtk.StringList.new(options))
        combo.set_selected(current_idx)
        group.add(combo)

        uid = f"{s['config_key']}|{s['config_file']}|{s.get('index_value','')}|{s.get('parent_key','')}"
        self.category_pending[cat_name][uid] = {
            "type":"dropdown", "combo":combo, "options":options,
            "config_file":s["config_file"], "config_key":s["config_key"],
            "parent_key":s["parent_key"], "index_field":s["index_field"],
            "index_value":s["index_value"], "original":current_idx, "format":s["format"],
            "mirror_files":s.get("mirror_files", []), "on_apply":s.get("on_apply", ""),
        }

    # ── Keybind ───────────────────────────────────────────────────────────────

    def _add_keybind(self, group, cat_name, s):
        """
        Zeigt eine expandierbare Row mit mehreren Unterfeldern.
        - Titel = gelesener description-Wert (oder label als Fallback)
        - visible = false in INI blendet die Row aus (für new_template Einträge)
        """
        # visible-Flag: Template-Einträge ausblenden
        if not s.get("visible", True):
            return

        fields       = s.get("fields", [])
        current_vals = read_keybind_fields(s["config_file"], s)

        # Titel: description-Wert aus der Datei, Fallback auf INI-label
        row_title = current_vals.get("description", "") or s["label"]

        # Modifier-Zusammenfassung als Subtitle
        use_mm = current_vals.get("use_mainmod","no") == "yes"
        mod    = current_vals.get("modifier","none")
        key    = current_vals.get("key","")
        parts  = []
        if use_mm:  parts.append("mainMod")
        if mod and mod != "none": parts.append(mod)
        if key: parts.append(key)
        subtitle = " + ".join(parts) if parts else ""

        exp_row = Adw.ExpanderRow()
        exp_row.set_title(row_title)
        if subtitle: exp_row.set_subtitle(subtitle)

        widgets = {}

        # Felder nach block-Namen gruppieren
        block_groups: dict = {}
        no_block: list     = []
        block_order: list  = []
        for field in fields:
            blk = field.get("block")
            if blk:
                if blk not in block_groups:
                    block_groups[blk] = []
                    block_order.append(blk)
                block_groups[blk].append(field)
            else:
                no_block.append(field)

        def _add_kf(container, field, fval):
            fkey = field.get("key",""); flabel = field.get("label", fkey)
            ftype = field.get("type","text"); fopts = field.get("options",[])
            if ftype == "dropdown":
                eff = list(fopts)
                if fval and fval not in eff: eff.insert(0, fval)
                fidx = eff.index(fval) if fval in eff else 0
                combo = Adw.ComboRow()
                combo.set_title(flabel)
                combo.set_model(Gtk.StringList.new(eff))
                combo.set_selected(fidx)
                container.add_row(combo)
                widgets[fkey] = ("dropdown", combo, eff)
            else:
                te = Adw.EntryRow(); te.set_title(flabel)
                te.set_text(str(fval))
                container.add_row(te)
                widgets[fkey] = ("text", te, [])

        for field in no_block:
            fval = current_vals.get(field.get("key",""), field.get("options",[""])[0] if field.get("options") else "")
            _add_kf(exp_row, field, fval)
        for blk_name in block_order:
            blk_row = Adw.ExpanderRow()
            blk_row.set_title(blk_name); blk_row.set_expanded(True)
            for field in block_groups[blk_name]:
                fval = current_vals.get(field.get("key",""), "")
                _add_kf(blk_row, field, fval)
            exp_row.add_row(blk_row)

        # Mülltonne-Button als Suffix im ExpanderRow-Header
        del_btn = Gtk.Button()
        del_btn.set_icon_name("user-trash-symbolic")
        del_btn.add_css_class("flat")
        del_btn.add_css_class("destructive-action")
        del_btn.set_tooltip_text(t("tooltip_delete"))
        del_btn.set_valign(Gtk.Align.CENTER)

        # Closure für delete-Callback
        def make_del_cb(entry_s, cat, grp, row):
            def cb(_btn):
                dialog = Adw.AlertDialog(
                    heading=t("delete_heading"),
                    body=f"\"{row.get_title()}\" wird dauerhaft aus der Datei entfernt.",
                )
                dialog.add_response("cancel", t("btn_cancel"))
                dialog.add_response("delete", t("btn_delete"))
                dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)
                dialog.set_default_response("cancel")
                def on_response(d, response):
                    if response != "delete": return
                    ok = delete_entry(entry_s["config_file"], entry_s)
                    if ok:
                        # Seite neu aufbauen damit die Row wirklich verschwindet
                        self._all_categories = load_categories(self.ini_path)
                        self._build_all_categories()
                        idx = list(self._all_categories.keys()).index(cat_name) if cat_name in self._all_categories else 0
                        sidebar_row = self._sidebar_list.get_row_at_index(idx)
                        if sidebar_row:
                            self._sidebar_list.select_row(sidebar_row)
                            self._show_category(sidebar_row.get_name())
                        toast = Adw.Toast(title=t("toast_entry_deleted"))
                        toast.set_timeout(3)
                        self._toast_overlay.add_toast(toast)
                    else:
                        self._show_error_dialog([t("error_delete_failed", file=entry_s['config_file'])])
                dialog.connect("response", on_response)
                dialog.present(self._win)
            return cb

        entry_snapshot = {
            "config_file": s["config_file"],
            "config_key":  s["config_key"],
            "parent_key":  s["parent_key"],
            "index_field": s["index_field"],
            "index_value": s["index_value"],
            "format":      s["format"],
        }
        del_btn.connect("clicked", make_del_cb(entry_snapshot, cat_name, group, exp_row))
        exp_row.add_suffix(del_btn)

        group.add(exp_row)

        uid = f"multisetting|{s['config_file']}|{s.get('index_value','')}|{s.get('config_key','')}|{id(exp_row)}"
        self.category_pending[cat_name][uid] = {
            "type":"multisetting", "widgets":widgets, "fields":fields,
            "config_file":s["config_file"], "config_key":s["config_key"],
            "parent_key":s["parent_key"], "index_field":s["index_field"],
            "index_value":s["index_value"], "format":s["format"],
            "lua_func":s.get("lua_func",""),
        }

    # ── Neuer Eintrag Dialog ──────────────────────────────────────────────────

    def _on_new_entry(self, _btn, cat_name, settings):
        """Öffnet Dialog zum Anlegen eines neuen Eintrags."""
        # Finde das new_template aus den settings
        tmpl_entry = next((s for s in settings if s.get("new_template")), None)
        if not tmpl_entry: return

        fields   = tmpl_entry.get("fields", [])
        template = tmpl_entry["new_template"]

        dialog = Adw.AlertDialog(
            heading=t("new_entry_heading"),
            body="Felder ausfüllen und bestätigen.",
        )

        # Felder-Box
        content_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        content_box.set_margin_top(8)
        content_box.set_size_request(400, -1)
        field_widgets = {}

        for field in fields:
            fkey   = field.get("key","")
            flabel = field.get("label", fkey)
            ftype  = field.get("type","text")
            fopts  = field.get("options", [])

            lbl = Gtk.Label(label=flabel)
            lbl.set_halign(Gtk.Align.START)
            lbl.add_css_class("dim-label")
            content_box.append(lbl)

            if ftype == "dropdown":
                dd = Gtk.DropDown.new_from_strings(fopts)
                dd.set_hexpand(True)
                content_box.append(dd)
                field_widgets[fkey] = ("dropdown", dd, fopts)
            else:
                entry = Gtk.Entry()
                entry.set_hexpand(True)
                entry.set_placeholder_text(flabel)
                content_box.append(entry)
                field_widgets[fkey] = ("text", entry, [])

        dialog.set_extra_child(content_box)
        dialog.add_response("cancel", t("btn_cancel"))
        dialog.add_response("create", t("btn_create"))
        dialog.set_default_response("create")
        dialog.set_response_appearance("create", Adw.ResponseAppearance.SUGGESTED)

        def on_response(d, response):
            if response != "create": return
            # Template mit Feldwerten befüllen
            filled = template
            for fkey, (ftype, widget, fopts) in field_widgets.items():
                if ftype == "dropdown":
                    idx = widget.get_selected()
                    val = fopts[idx] if idx < len(fopts) else ""
                else:
                    val = widget.get_text()
                filled = filled.replace(f"{{{fkey}}}", val)

            raw_vals = {k: (fopts[w.get_selected()] if ft=="dropdown" else w.get_text())
                         for k,(ft,w,fopts) in field_widgets.items()}
            raw_vals["__lua_func__"]   = tmpl_entry.get("lua_func", "hl.unknown")
            raw_vals["__field_defs__"] = tmpl_entry.get("fields", [])
            filled = filled.replace("\\n", "\n")
            ok = append_new_entry(tmpl_entry["append_file"], filled, vals=raw_vals)
            if ok:
                # Seite neu aufbauen
                self._all_categories = load_categories(self.ini_path)
                self._build_all_categories()
                # Zur Kategorie navigieren
                idx = list(self._all_categories.keys()).index(cat_name) if cat_name in self._all_categories else 0
                row = self._sidebar_list.get_row_at_index(idx)
                if row:
                    self._sidebar_list.select_row(row)
                    self._show_category(row.get_name())
                toast = Adw.Toast(title=t("toast_entry_created"))
                toast.set_timeout(3)
                self._toast_overlay.add_toast(toast)
            else:
                self._show_error_dialog([f"Konnte nicht schreiben: {tmpl_entry['append_file']}"])

        def resolve_template(template: str, field_widgets: dict) -> str:
            """Ersetzt {key} Platzhalter, löst mainMod-Kombination auf."""
            vals = {}
            for fkey, (ftype, widget, fopts) in field_widgets.items():
                if ftype == "dropdown":
                    idx = widget.get_selected()
                    vals[fkey] = fopts[idx] if idx < len(fopts) else ""
                else:
                    vals[fkey] = widget.get_text()

            # mainMod-Kombination: use_mainmod + modifier → use_mainmod_prefix + modifier_suffix
            use_mm  = vals.get("use_mainmod", "yes") == "yes"
            mod     = vals.get("modifier", "none")
            if use_mm and mod != "none":
                vals["use_mainmod_prefix"] = "mainMod .. "
                vals["modifier_suffix"]    = f'"{mod}" .. '
            elif use_mm:
                vals["use_mainmod_prefix"] = "mainMod .. "
                vals["modifier_suffix"]    = ""
            else:
                vals["use_mainmod_prefix"] = ""
                vals["modifier_suffix"]    = f'"{mod}" .. ' if mod != "none" else ""

            filled = template
            for k, v in vals.items():
                filled = filled.replace(f"{{{k}}}", v)
            return filled

        dialog.connect("response", lambda d, r: on_response_wrap(d, r, resolve_template))

        def on_response_wrap(d, response, resolve_fn):
            if response != "create": return
            filled = resolve_fn(template, field_widgets)
            filled = filled.replace("\\n", "\n")
            ok = append_new_entry(tmpl_entry["append_file"], filled, vals={k: (fopts[w.get_selected()] if ft=="dropdown" else w.get_text()) for k,(ft,w,fopts) in field_widgets.items()})
            if ok:
                self._all_categories = load_categories(self.ini_path)
                self._build_all_categories()
                idx = list(self._all_categories.keys()).index(cat_name) if cat_name in self._all_categories else 0
                row = self._sidebar_list.get_row_at_index(idx)
                if row:
                    self._sidebar_list.select_row(row)
                    self._show_category(row.get_name())
                toast = Adw.Toast(title=t("toast_entry_created"))
                toast.set_timeout(3)
                self._toast_overlay.add_toast(toast)
            else:
                self._show_error_dialog([f"Konnte nicht schreiben: {tmpl_entry['append_file']}"])

        dialog.present(self._win)

    # ── sArch: Hilfen ─────────────────────────────────────────────────────────

    def _toast(self, title: str):
        toast = Adw.Toast(title=title)
        toast.set_timeout(3)
        self._toast_overlay.add_toast(toast)

    # ── sArch: Hintergrundbild ────────────────────────────────────────────────

    def _add_wallpaper_group(self, outer_box, cat_name, s):
        """Wallpaper anklicken -> Popover mit Akzentfarben -> Farbe anklicken = sofort anwenden."""
        ex      = s.get("extra", {})
        wp_dir  = _x(ex.get("wallpaper_dir", "~/Bilder/Wallpapers"))
        cache   = _x(ex.get("cache_dir", "~/.cache/Wallpaper_thumbs"))
        cur, cur_idx = read_current_wallpaper()
        state = {"cur": cur, "idx": cur_idx, "colors": {}, "busy": False,
                 "popover": None, "css": {}}

        grp = Adw.PreferencesGroup()
        grp.set_title(s["label"] or t("wp_group"))
        grp.set_description(s["description"] or t("wp_group_desc"))

        preview = Gtk.Picture()
        preview.set_content_fit(Gtk.ContentFit.COVER)
        preview.set_can_shrink(True)
        preview.set_size_request(-1, 220)
        preview.add_css_class("card")
        if cur and os.path.exists(cur):
            preview.set_filename(cur)
        grp.add(preview)

        cur_label = Gtk.Label(label=os.path.basename(cur) if cur else "")
        cur_label.add_css_class("dim-label"); cur_label.set_margin_top(6)
        grp.add(cur_label)

        flow = Gtk.FlowBox()
        flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        flow.set_activate_on_single_click(True)
        flow.set_homogeneous(True)
        flow.set_min_children_per_line(3)
        flow.set_max_children_per_line(8)
        flow.set_row_spacing(6); flow.set_column_spacing(6)
        flow.set_margin_top(12)
        grp.add(flow)

        empty = Gtk.Label(label=t("wp_empty", dir=wp_dir))
        empty.add_css_class("dim-label"); empty.set_wrap(True)
        empty.set_visible(False)
        grp.add(empty)
        outer_box.append(grp)

        swatch_css = Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), swatch_css, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1)

        def ensure_css(cols):
            new = False
            for c in cols:
                k = c[1:].lower()
                if k in state["css"]: continue
                state["css"][k] = (f".sarch-sw-{k} {{ background-image:none; background-color:{c};"
                                   f" color:{_contrast(c)}; min-width:44px; min-height:44px;"
                                   f" padding:0; border-radius:9999px; }}\n"
                                   f".sarch-sw-{k}:hover {{ box-shadow: inset 0 0 0 3px alpha({_contrast(c)}, .6); }}\n")
                new = True
            if new:
                swatch_css.load_from_string("".join(state["css"].values()))

        def select_path(path):
            child = flow.get_first_child()
            while child:
                if child.get_name() == path:
                    flow.select_child(child); return child
                child = child.get_next_sibling()
            flow.unselect_all()
            return None

        def close_popover():
            pop = state["popover"]
            if pop:
                state["popover"] = None
                pop.popdown()
                if pop.get_parent(): pop.unparent()

        def apply(wp, idx, color):
            if state["busy"]: return
            state["busy"] = True
            close_popover()
            self._toast(t("wp_applying"))
            def done(ok, err):
                state["busy"] = False
                if ok:
                    state["cur"], state["idx"] = wp, idx
                    preview.set_filename(wp)
                    cur_label.set_label(os.path.basename(wp))
                    select_path(wp)
                    apply_matugen_theme()           # Farben der Settings-App gleich mitziehen
                    self._toast(t("wp_applied", name=os.path.basename(wp)))
                else:
                    select_path(state["cur"])
                    self._show_error_dialog([f"{t('wp_failed')}: {err}"])
                return False
            def work():
                ok, err = apply_wallpaper(wp, idx, cache, color)
                GLib.idle_add(done, ok, err)
            threading.Thread(target=work, daemon=True).start()

        def fill_popover(body, wp, cols):
            while (c := body.get_first_child()): body.remove(c)
            if cols is None:                        # lädt noch
                sp = Gtk.Spinner(); sp.start()
                lb = Gtk.Label(label=t("wp_color_loading")); lb.add_css_class("dim-label")
                body.append(sp); body.append(lb)
                return
            if not cols:                            # matugen lieferte nichts
                lb = Gtk.Label(label=t("wp_color_failed")); lb.add_css_class("dim-label")
                lb.set_wrap(True); lb.set_max_width_chars(28)
                b = Gtk.Button(label=t("wp_default_color")); b.add_css_class("suggested-action")
                b.connect("clicked", lambda *_: apply(wp, 0, ""))
                body.append(lb); body.append(b)
                return
            ensure_css(cols)
            for i, c in enumerate(cols):
                b = Gtk.Button()
                b.add_css_class(f"sarch-sw-{c[1:].lower()}")
                b.set_tooltip_text(c)
                if wp == state["cur"] and i == state["idx"]:
                    b.set_child(Gtk.Image.new_from_icon_name("object-select-symbolic"))
                b.connect("clicked", lambda _b, i=i, c=c: apply(wp, i, c))
                body.append(b)

        def on_activated(_fb, child):
            if state["busy"]: return
            close_popover()
            wp = child.get_name()
            preview.set_filename(wp)                # Vorschau schon beim Anklicken

            pop = Gtk.Popover()
            pop.set_parent(child)
            pop.set_position(Gtk.PositionType.BOTTOM)
            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
            box.set_margin_top(8); box.set_margin_bottom(8)
            box.set_margin_start(10); box.set_margin_end(10)
            title = Gtk.Label(label=t("wp_pick_color")); title.add_css_class("heading")
            name = Gtk.Label(label=os.path.basename(wp)); name.add_css_class("dim-label")
            name.set_ellipsize(Pango.EllipsizeMode.MIDDLE); name.set_max_width_chars(30)
            body = Gtk.Box(spacing=8); body.set_halign(Gtk.Align.CENTER)
            box.append(title); box.append(name); box.append(body)
            pop.set_child(box)

            def on_closed(p):
                # Vorschau zurück, wenn nichts angewendet wurde
                if not state["busy"] and state["cur"] and os.path.exists(state["cur"]):
                    preview.set_filename(state["cur"])
                    select_path(state["cur"])
                if state["popover"] is p: state["popover"] = None
                GLib.idle_add(lambda: (p.unparent() if p.get_parent() else None, False)[1])
            pop.connect("closed", on_closed)
            state["popover"] = pop

            cols = state["colors"].get(wp)
            fill_popover(body, wp, cols)
            pop.popup()
            if cols is None:
                def show(cols):
                    state["colors"][wp] = cols
                    if state["popover"] is pop:
                        fill_popover(body, wp, cols)
                    return False
                def work():
                    c = matugen_source_colors(wp)
                    GLib.idle_add(show, c)
                threading.Thread(target=work, daemon=True).start()

        def thumb_widget(wp):
            th = thumb_path(cache, wp)
            if os.path.exists(th):
                w = Gtk.Picture.new_for_filename(th)
                w.set_content_fit(Gtk.ContentFit.COVER); w.set_can_shrink(True)
            else:
                w = Gtk.Image.new_from_icon_name("image-x-generic-symbolic")
                w.set_pixel_size(32)
            w.set_size_request(100, 100)
            return w

        def populate():
            close_popover()
            flow.remove_all()
            wps = list_wallpapers(wp_dir)
            empty.set_visible(not wps)
            for wp in wps:
                child = Gtk.FlowBoxChild()
                child.set_child(thumb_widget(wp))
                child.set_name(wp)
                child.set_tooltip_text(os.path.basename(wp))
                flow.append(child)
            if state["cur"]:
                select_path(state["cur"])
            return False

        flow.connect("child-activated", on_activated)
        populate()

        def refresh_thumbs():
            # Vorschaubilder an Ort und Stelle tauschen, damit ein offenes Popover bleibt
            names, child = [], flow.get_first_child()
            while child:
                names.append(child.get_name())
                child.set_child(thumb_widget(child.get_name()))
                child = child.get_next_sibling()
            if names != list_wallpapers(wp_dir) and not state["popover"]:
                populate()                          # neue/entfernte Bilder
            return False

        def make_thumbs():
            if ensure_thumbnails(wp_dir, cache):
                GLib.idle_add(refresh_thumbs)
        threading.Thread(target=make_thumbs, daemon=True).start()

    # ── sArch: Schriften ──────────────────────────────────────────────────────

    def _font_button(self, family: str, mono: bool) -> Gtk.FontDialogButton:
        dlg = Gtk.FontDialog()
        dlg.set_modal(True)
        if mono:
            dlg.set_filter(Gtk.CustomFilter.new(_is_mono_font))
        btn = Gtk.FontDialogButton.new(dlg)
        btn.set_level(Gtk.FontLevel.FAMILY)
        btn.set_use_font(True)
        btn.set_valign(Gtk.Align.CENTER)
        self._set_font_family(btn, family)
        return btn

    @staticmethod
    def _set_font_family(btn, family: str):
        if family:
            d = Pango.FontDescription()
            d.set_family(family)
            btn.set_font_desc(d)

    @staticmethod
    def _get_font_family(btn, fallback: str) -> str:
        d = btn.get_font_desc()
        return (d.get_family() if d else "") or fallback

    def _add_fonts_group(self, outer_box, cat_name, s):
        ex     = s.get("extra", {})
        dunst  = _split_paths(ex.get("dunst_files", "~/.config/dunst/dunstrc"))
        rofi   = _split_paths(ex.get("rofi_files", "~/.config/rofi/colors.rasi"))
        kitty  = _x(ex.get("kitty_file", "~/.config/kitty/hyde.conf"))
        ui_fam, ui_size = read_ui_font(rofi, dunst)
        k_fam,  k_size  = read_kitty_font(kitty)
        orig = {"ui": (ui_fam, ui_size or 12.0), "k": (k_fam, k_size or 10.0)}

        def cur(v): return t("font_current", value=v if v not in ("", None) else "–")

        # Oberfläche (Dunst & Rofi)
        g1 = Adw.PreferencesGroup()
        g1.set_title(t("font_ui_group"))
        g1.set_description(s["description"] or t("font_ui_desc"))
        ui_btn = self._font_button(ui_fam, mono=False)
        ui_row = Adw.ActionRow(title=t("font_family"), subtitle=cur(ui_fam))
        ui_row.add_suffix(ui_btn); ui_row.set_activatable_widget(ui_btn)
        ui_spin = Adw.SpinRow.new_with_range(4, 72, 1)
        ui_spin.set_title(t("font_size")); ui_spin.set_subtitle(cur(_fmt_size(orig["ui"][1]) if ui_size else ""))
        ui_spin.set_value(orig["ui"][1])
        g1.add(ui_row); g1.add(ui_spin)
        outer_box.append(g1)

        # Terminal (kitty)
        g2 = Adw.PreferencesGroup()
        g2.set_title(t("font_term_group"))
        g2.set_description(t("font_term_desc"))
        k_btn = self._font_button(k_fam, mono=True)
        k_row = Adw.ActionRow(title=t("font_family"), subtitle=cur(k_fam))
        k_row.add_suffix(k_btn); k_row.set_activatable_widget(k_btn)
        k_spin = Adw.SpinRow.new_with_range(4, 48, 0.5)
        k_spin.set_digits(1)
        k_spin.set_title(t("font_size")); k_spin.set_subtitle(cur(_fmt_size(orig["k"][1]) if k_size else ""))
        k_spin.set_value(orig["k"][1])
        g2.add(k_row); g2.add(k_spin)
        outer_box.append(g2)

        def apply():
            ok = True
            nf, ns = self._get_font_family(ui_btn, orig["ui"][0]), ui_spin.get_value()
            if nf and (nf, ns) != orig["ui"]:
                failed = write_ui_font(dunst, rofi, nf, ns)
                ok = ok and not failed
                if not failed:
                    orig["ui"] = (nf, ns)
                    ui_row.set_subtitle(cur(nf)); ui_spin.set_subtitle(cur(_fmt_size(ns)))
                    _spawn(["dunstctl", "reload"])
                    _notify("Font changed", f"{nf} {_fmt_size(ns)}")
            nf, ns = self._get_font_family(k_btn, orig["k"][0]), k_spin.get_value()
            if nf and (nf, ns) != orig["k"]:
                w1 = _replace_in_file(kitty, _RE_KITTY_FAM, nf)
                w2 = _replace_in_file(kitty, _RE_KITTY_SIZE, _fmt_size(ns))
                ok = ok and w1 and w2
                if w1 and w2:
                    orig["k"] = (nf, ns)
                    k_row.set_subtitle(cur(nf)); k_spin.set_subtitle(cur(_fmt_size(ns)))
                    _spawn(["pkill", "-USR1", "-x", "kitty"])
                    _notify("Terminal font changed", f"{nf} {_fmt_size(ns)}")
            return ok

        def reset():
            self._set_font_family(ui_btn, orig["ui"][0]); ui_spin.set_value(orig["ui"][1])
            self._set_font_family(k_btn,  orig["k"][0]);  k_spin.set_value(orig["k"][1])

        self.category_pending[cat_name][f"fonts|{kitty}"] = {
            "type": "custom", "apply": apply, "reset": reset,
            "config_key": s["label"] or "fonts", "config_file": ", ".join(dunst + rofi + [kitty]),
        }

    # ── Kategorie anzeigen ────────────────────────────────────────────────────

    def _show_category(self, cat_name: str):
        widget = self._category_widgets.get(cat_name)
        if widget:
            self._content_page.set_title(cat_name)
            self._content_toolbar.set_content(widget)

    # ── Apply / Reset ─────────────────────────────────────────────────────────

    def _on_reset(self, _btn, cat_name: str):
        for entry in self.category_pending.get(cat_name, {}).values():
            if entry["type"] == "slider":
                entry["scale"].set_value(entry["original"])
            elif entry["type"] == "dropdown":
                entry["combo"].set_selected(entry["original"])
            elif entry["type"] in ("variable","autostart"):
                entry["entry"].set_text(entry["original"])
            elif entry["type"] in ("animation","workspace_rule","layer_rule"):
                for fk,(ft,w,opts) in entry["widgets"].items():
                    orig_val = entry["original"].get(fk,"")
                    if ft == "dropdown":
                        eff = list(opts)
                        if orig_val and orig_val not in eff: eff.insert(0,orig_val)
                        w.set_selected(eff.index(orig_val) if orig_val in eff else 0)
                    else:
                        w.set_text(str(orig_val))
            elif entry["type"] == "custom":
                entry["reset"]()
            # keybind: kein Reset implementiert (komplex, später erweiterbar)

    def _on_apply(self, _btn, cat_name: str):
        errors = []
        post_cmds = []
        for entry in self.category_pending.get(cat_name, {}).values():
            if entry["type"] == "slider":
                step = entry["scale"].get_adjustment().get_step_increment()
                raw  = entry["scale"].get_value()
                val  = round(raw/step)*step if step>0 else raw
                ok   = write_value(entry["config_file"], entry, val)
                if ok:
                    if val != entry["original"]:
                        errors += self._write_mirrors(entry, val, post_cmds)
                    entry["original"] = val

            elif entry["type"] == "dropdown":
                idx = entry["combo"].get_selected()
                val = entry["options"][idx] if idx < len(entry["options"]) else ""
                ok  = write_value(entry["config_file"], entry, val)
                if ok:
                    if idx != entry["original"]:
                        errors += self._write_mirrors(entry, val, post_cmds)
                    entry["original"] = idx

            elif entry["type"] == "multisetting":
                fvals = {}
                for fkey, (ftype, widget, fopts) in entry["widgets"].items():
                    if ftype == "dropdown":
                        idx = widget.get_selected()
                        fvals[fkey] = fopts[idx] if idx < len(fopts) else ""
                    else:
                        fvals[fkey] = widget.get_text()
                # field_defs für lua_func Builder mitgeben
                if entry.get("lua_func"):
                    fvals["__field_defs__"] = entry.get("fields", [])
                ok = write_keybind_fields(entry["config_file"], entry, fvals)

            elif entry["type"] == "variable":
                val = entry["entry"].get_text()
                ok  = write_variable(entry["config_file"], entry["line_idx"],
                                     entry["var_name"], val)
                if ok: entry["original"] = val
            elif entry["type"] == "autostart":
                val = entry["entry"].get_text()
                ok  = write_autostart(entry["config_file"], entry["line_idx"], val)
                if ok: entry["original"] = val
            elif entry["type"] in ("animation","workspace_rule","layer_rule"):
                fvals = {}
                for fk,(ft,w,opts) in entry["widgets"].items():
                    if ft == "dropdown":
                        idx = w.get_selected()
                        fvals[fk] = opts[idx] if idx < len(opts) else ""
                    else:
                        fvals[fk] = w.get_text()
                fvals["_line"] = entry["line_idx"]
                ok = entry["writer"](entry["config_file"], entry["line_idx"], fvals)
                if ok: entry["original"] = dict(fvals)
            elif entry["type"] == "custom":
                ok = entry["apply"]()
            else:
                ok = True

            if not ok:
                errors.append(f"{entry.get('config_key','?')} [{entry.get('index_value','')}] → {entry.get('config_file','')}")

        for cmd in post_cmds:
            _spawn(["bash", "-c", cmd])

        if errors:
            self._show_error_dialog(errors)
        else:
            toast = Adw.Toast(title=t("toast_applied", category=cat_name))
            toast.set_timeout(3)
            self._toast_overlay.add_toast(toast)

    def _write_mirrors(self, entry: dict, val, post_cmds: list) -> list:
        """Gleichen Wert in mirror_files schreiben (z.B. Matugen-Template), on_apply vormerken."""
        errs = []
        for mf in entry.get("mirror_files", []):
            if os.path.exists(mf) and not write_value(mf, entry, val):
                errs.append(f"{entry.get('config_key','?')} → {mf}")
        cmd = entry.get("on_apply", "")
        if cmd and cmd not in post_cmds:
            post_cmds.append(cmd)
        return errs

    def _show_error_dialog(self, failed: list):
        body = t("error_body", entries="\n".join(f"• {e}" for e in failed))
        dialog = Adw.AlertDialog(heading=t("error_heading"), body=body)
        dialog.add_response("ok", t("btn_ok"))
        dialog.set_default_response("ok")
        dialog.present(self._win)


# ── Entry Point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="settings_mask – Hyprland Lua config UI")
    parser.add_argument("ini", nargs="?", default="settings.ini", help="Path to settings.ini")
    parser.add_argument("--lang", default="", help="Language code (e.g. en, de). Auto-detected if omitted.")
    parser.add_argument("--page", default="", help="Open this category (name or INI section, e.g. wallpaper)")
    args = parser.parse_args()
    if not os.path.exists(args.ini):
        print(f"INI file not found: {args.ini}", file=sys.stderr)
        sys.exit(1)
    app = SettingsApp(args.ini, lang=args.lang, page=args.page)
    sys.exit(app.run([]))