#!/usr/bin/env python3
"""
settings_mask.py – Libadwaita Settings UI mit Kategorien-Navigation
und Matugen-Colorscheme-Unterstützung.

Abhängigkeiten:
    sudo pacman -S python-gobject libadwaita

Verwendung:
    python settings_mask.py [settings.ini]
"""

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, Gdk
import configparser
import subprocess
import os
import sys
import re


# ── Matugen Colorscheme laden ─────────────────────────────────────────────────

MATUGEN_PATHS = [
    os.path.expanduser("~/.themes/Matugen/gtk-4.0/colors.css"),
    os.path.expanduser("~/.cache/matugen/colors.css"),
    os.path.expanduser("~/.config/matugen/colors.css"),
]

def load_matugen_css() -> str | None:
    """Sucht nach der matugen colors.css und gibt den Inhalt zurück."""
    for path in MATUGEN_PATHS:
        if os.path.exists(path):
            try:
                with open(path) as f:
                    return f.read()
            except OSError:
                pass
    return None

def apply_matugen_theme():
    """
    Das Matugen GTK-CSS enthält fertige CSS-Regeln für scale, progressbar etc.
    Wir laden die Datei direkt als GTK CssProvider – keine eigene Farbextraktion nötig.
    Zusätzlich extrahieren wir die Hex-Werte für den Übernehmen-Button.
    """
    raw = load_matugen_css()
    if not raw:
        return False

    # Alle Hex-Farben aus dem CSS extrahieren (Reihenfolge: erste = primary, zweite = secondary)
    hex_colors = re.findall(r'#[0-9a-fA-F]{6}', raw)
    primary   = hex_colors[0] if len(hex_colors) > 0 else None
    secondary = hex_colors[1] if len(hex_colors) > 1 else None

    # Das originale Matugen-CSS direkt laden (scale, trough etc. werden damit gestylt)
    css = raw

    # Zusätzlich: Übernehmen-Button und Sidebar-Selektion mit primary färben
    if primary:
        # Hellere Variante für Hover manuell berechnen
        r = int(primary[1:3], 16)
        g = int(primary[3:5], 16)
        b = int(primary[5:7], 16)
        r2 = min(255, int(r * 1.15))
        g2 = min(255, int(g * 1.15))
        b2 = min(255, int(b * 1.15))
        primary_hover = f"#{r2:02x}{g2:02x}{b2:02x}"
        # Textfarbe: dunkel auf hellen Farben, hell auf dunklen
        luminance = 0.299 * r + 0.587 * g + 0.114 * b
        text_color = "#1a1a1a" if luminance > 140 else "#ffffff"

        css += f"""
@define-color matugen_primary {primary};
@define-color matugen_primary_hover {primary_hover};
@define-color matugen_text {text_color};

button.suggested-action {{
  background-image: none;
  background-color: @matugen_primary;
  color: @matugen_text;
  box-shadow: none;
  border: none;
}}
button.suggested-action:hover {{
  background-image: none;
  background-color: @matugen_primary_hover;
  color: @matugen_text;
}}
button.suggested-action:active {{
  background-image: none;
  background-color: @matugen_primary;
  color: @matugen_text;
}}
.navigation-sidebar row:selected {{
  background-color: @matugen_primary;
  color: @matugen_text;
}}
.navigation-sidebar row:selected * {{
  color: @matugen_text;
}}
"""

    provider = Gtk.CssProvider()
    provider.load_from_string(css)
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(),
        provider,
        Gtk.STYLE_PROVIDER_PRIORITY_USER,
    )
    return True


# ── INI laden ─────────────────────────────────────────────────────────────────

def load_categories(ini_path: str) -> dict[str, list[dict]]:
    """
    Liest die INI und gruppiert Einstellungen nach [category "Name"] Sektionen.
    Format:
        [category "Allgemein"]
        [gaps_out]
        category = Allgemein
        label = Äußere Ränder
        ...
    Alternativ: category-Feld direkt in jeder Sektion.
    Sektionen ohne category landen in "Allgemein".
    """
    cfg = configparser.ConfigParser()
    cfg.read(ini_path)

    # Kategorien-Reihenfolge merken
    categories: dict[str, list[dict]] = {}

    for section in cfg.sections():
        s = cfg[section]
        cat = s.get("category", "Allgemein")

        entry = {
            "label":       s.get("label", section),
            "description": s.get("description", ""),
            "min":         float(s.get("min", 0)),
            "max":         float(s.get("max", 100)),
            "step":        float(s.get("step", 1)),
            "config_file": s.get("config_file", ""),
            "config_key":  s.get("config_key", ""),
            "format":      s.get("format", "hypr"),
        }

        if cat not in categories:
            categories[cat] = []
        categories[cat].append(entry)

    return categories


# ── Wert lesen ────────────────────────────────────────────────────────────────

def read_current_value(config_file: str, config_key: str, fallback: float) -> float:
    if not config_file or not os.path.exists(config_file):
        return fallback
    try:
        with open(config_file) as f:
            for line in f:
                stripped = line.strip()
                if not (stripped.startswith(config_key) and
                        len(stripped) > len(config_key) and
                        stripped[len(config_key)] in ("=", " ")):
                    continue
                parts = stripped.split("=", 1)
                if len(parts) == 2:
                    raw = parts[1].strip().rstrip(",").split("--")[0].strip()
                    return float(raw)
    except (OSError, ValueError):
        pass
    return fallback


# ── Wert schreiben ────────────────────────────────────────────────────────────

def write_value(config_file: str, config_key: str, value: float, fmt: str = "hypr") -> bool:
    if not config_file:
        return False

    int_val = int(value)

    if fmt == "lua":
        sed_expr = f"s|^(\\s*){config_key}\\s*=\\s*[^,]*(,?)|\\1{config_key} = {int_val}\\2|"
    else:
        sed_expr = f"s|^(\\s*){config_key}\\s*=.*|\\1{config_key} = {int_val}|"

    result = subprocess.run(
        ["sed", "-E", "-i", sed_expr, config_file],
        capture_output=True, text=True,
    )
    return result.returncode == 0


# ── GTK4 / Adwaita App ────────────────────────────────────────────────────────

class SettingsApp(Adw.Application):
    def __init__(self, ini_path: str):
        super().__init__(application_id="de.local.settings-mask")
        self.ini_path = ini_path
        self.pending: dict[str, dict] = {}
        # pro Kategorie eigene pending-Gruppe
        self.category_pending: dict[str, dict[str, dict]] = {}
        self.connect("activate", self.on_activate)

    def on_activate(self, app):
        categories = load_categories(self.ini_path)

        # Matugen Theme anwenden (Dark Mode immer aktiv)
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK)
        matugen_ok = apply_matugen_theme()

        # Hauptfenster
        win = Adw.ApplicationWindow(application=app)
        win.set_title("Einstellungen")
        win.set_default_size(720, 520)
        win.set_resizable(True)
        self._win = win

        # Toast-Overlay als Root
        self._toast_overlay = Adw.ToastOverlay()

        # NavigationSplitView: links Sidebar, rechts Content
        split = Adw.NavigationSplitView()
        split.set_min_sidebar_width(180)
        split.set_max_sidebar_width(240)

        # ── Sidebar ───────────────────────────────────────────────────────────
        sidebar_page = Adw.NavigationPage(title="Kategorien")
        sidebar_toolbar = Adw.ToolbarView()
        sidebar_header = Adw.HeaderBar()
        sidebar_toolbar.add_top_bar(sidebar_header)

        sidebar_scroll = Gtk.ScrolledWindow()
        sidebar_scroll.set_vexpand(True)
        sidebar_scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        sidebar_list = Gtk.ListBox()
        sidebar_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        sidebar_list.add_css_class("navigation-sidebar")
        sidebar_list.set_margin_top(8)
        sidebar_list.set_margin_bottom(8)
        sidebar_list.set_margin_start(8)
        sidebar_list.set_margin_end(8)

        sidebar_scroll.set_child(sidebar_list)
        sidebar_toolbar.set_content(sidebar_scroll)
        sidebar_page.set_child(sidebar_toolbar)
        split.set_sidebar(sidebar_page)

        # ── Content-Bereich ───────────────────────────────────────────────────
        self._content_page = Adw.NavigationPage(title="Einstellungen")
        self._content_toolbar = Adw.ToolbarView()
        content_header = Adw.HeaderBar()
        self._content_toolbar.add_top_bar(content_header)
        self._content_page.set_child(self._content_toolbar)
        split.set_content(self._content_page)

        # ── Kategorie-Seiten bauen ─────────────────────────────────────────────
        self._category_widgets: dict[str, Gtk.Widget] = {}

        for cat_name, settings in categories.items():
            self.category_pending[cat_name] = {}
            page_widget = self._build_category_page(cat_name, settings)
            self._category_widgets[cat_name] = page_widget

            # Sidebar-Eintrag
            row = Gtk.ListBoxRow()
            row_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            row_box.set_margin_top(10)
            row_box.set_margin_bottom(10)
            row_box.set_margin_start(12)
            row_box.set_margin_end(12)
            icon = Gtk.Image.new_from_icon_name("preferences-system-symbolic")
            label = Gtk.Label(label=cat_name)
            label.set_halign(Gtk.Align.START)
            label.set_hexpand(True)
            row_box.append(icon)
            row_box.append(label)
            row.set_child(row_box)
            row.set_name(cat_name)
            sidebar_list.append(row)

        # Ersten Eintrag selektieren
        first_row = sidebar_list.get_row_at_index(0)
        if first_row:
            sidebar_list.select_row(first_row)
            first_cat = first_row.get_name()
            self._show_category(first_cat)

        sidebar_list.connect("row-selected", self._on_category_selected)

        self._toast_overlay.set_child(split)
        win.set_content(self._toast_overlay)
        win.present()

    # ── Kategorie-Seite bauen ─────────────────────────────────────────────────

    def _build_category_page(self, cat_name: str, settings: list[dict]) -> Gtk.Widget:
        """Baut den Scroll+Clamp+Box Inhalt für eine Kategorie."""
        scroll = Gtk.ScrolledWindow()
        scroll.set_vexpand(True)
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)

        clamp = Adw.Clamp()
        clamp.set_maximum_size(640)
        clamp.set_margin_top(16)
        clamp.set_margin_bottom(16)
        clamp.set_margin_start(16)
        clamp.set_margin_end(16)

        outer_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=20)

        pref_group = Adw.PreferencesGroup()
        pref_group.set_title(cat_name)
        pref_group.set_description('Werte anpassen und mit "Übernehmen" bestätigen.')

        for s in settings:
            current = read_current_value(s["config_file"], s["config_key"], s["min"])
            current = max(s["min"], min(s["max"], current))

            # Label-Zeile mit Wert rechts
            row = Adw.ActionRow()
            row.set_title(s["label"])
            if s["description"]:
                row.set_subtitle(s["description"])
            row.set_activatable(False)

            value_label = Gtk.Label(label=str(int(current)))
            value_label.set_width_chars(3)
            value_label.set_xalign(1.0)
            value_label.add_css_class("numeric")
            value_label.add_css_class("dim-label")
            row.add_suffix(value_label)

            # Slider-Zeile
            slider_row = Adw.ActionRow()
            slider_row.set_activatable(False)

            adj = Gtk.Adjustment(
                value=current,
                lower=s["min"],
                upper=s["max"],
                step_increment=s["step"],
                page_increment=s["step"] * 5,
            )
            scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL, adjustment=adj)
            # Wert nach Scale-Erstellung nochmal explizit setzen damit GTK ihn nicht verändert
            scale.set_value(current)
            scale.set_hexpand(True)
            scale.set_draw_value(False)
            scale.set_digits(0)
            scale.set_margin_start(8)
            scale.set_margin_end(8)
            scale.set_margin_top(4)
            scale.set_margin_bottom(4)
            scale.add_mark(s["min"], Gtk.PositionType.BOTTOM, str(int(s["min"])))
            scale.add_mark(s["max"], Gtk.PositionType.BOTTOM, str(int(s["max"])))

            uid = s["config_key"] + "|" + s["config_file"]
            self.category_pending[cat_name][uid] = {
                "scale":       scale,
                "config_file": s["config_file"],
                "config_key":  s["config_key"],
                "original":    current,
                "format":      s.get("format", "hypr"),
            }
            # Auch in globalem pending für Reset-All
            self.pending[uid] = self.category_pending[cat_name][uid]

            def make_cb(vl, sc):
                def cb(_):
                    raw  = sc.get_value()
                    step = sc.get_adjustment().get_step_increment()
                    snapped = round(raw / step) * step if step > 0 else raw
                    vl.set_label(str(int(snapped)))
                return cb

            scale.connect("value-changed", make_cb(value_label, scale))
            slider_row.add_prefix(scale)

            pref_group.add(row)
            pref_group.add(slider_row)

        outer_box.append(pref_group)

        # Button-Leiste
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        btn_box.set_halign(Gtk.Align.END)
        btn_box.set_margin_top(4)

        reset_btn = Gtk.Button(label="Zurücksetzen")
        reset_btn.add_css_class("flat")
        reset_btn.connect("clicked", self._on_reset_category, cat_name)

        apply_btn = Gtk.Button(label="Übernehmen")
        apply_btn.add_css_class("suggested-action")
        apply_btn.connect("clicked", self._on_apply_category, cat_name)

        btn_box.append(reset_btn)
        btn_box.append(apply_btn)
        outer_box.append(btn_box)

        clamp.set_child(outer_box)
        scroll.set_child(clamp)
        return scroll

    # ── Kategorie anzeigen ────────────────────────────────────────────────────

    def _show_category(self, cat_name: str):
        widget = self._category_widgets.get(cat_name)
        if widget:
            self._content_page.set_title(cat_name)
            self._content_toolbar.set_content(widget)

    def _on_category_selected(self, listbox, row):
        if row:
            self._show_category(row.get_name())

    # ── Apply / Reset pro Kategorie ───────────────────────────────────────────

    def _on_reset_category(self, _btn, cat_name: str):
        for entry in self.category_pending.get(cat_name, {}).values():
            entry["scale"].set_value(entry["original"])

    def _on_apply_category(self, _btn, cat_name: str):
        errors = []
        for entry in self.category_pending.get(cat_name, {}).values():
            raw  = entry["scale"].get_value()
            step = entry["scale"].get_adjustment().get_step_increment()
            val  = round(raw / step) * step if step > 0 else raw
            ok   = write_value(entry["config_file"], entry["config_key"], val, entry.get("format", "hypr"))
            if not ok:
                errors.append(f"{entry['config_key']} → {entry['config_file']}")
            else:
                entry["original"] = val

        if errors:
            self._show_error_dialog(errors)
        else:
            toast = Adw.Toast(title=f'"{cat_name}" erfolgreich übernommen.')
            toast.set_timeout(3)
            self._toast_overlay.add_toast(toast)

    # ── Fehler-Dialog ─────────────────────────────────────────────────────────

    def _show_error_dialog(self, failed: list[str]):
        dialog = Adw.MessageDialog(
            transient_for=self._win,
            heading="Fehler beim Schreiben",
            body="Folgende Einstellungen konnten nicht gespeichert werden:\n\n"
                 + "\n".join(f"• {e}" for e in failed)
                 + "\n\nBitte Dateipfade und Berechtigungen prüfen.",
        )
        dialog.add_response("ok", "OK")
        dialog.set_default_response("ok")
        dialog.present()


# ── Entry Point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    ini = sys.argv[1] if len(sys.argv) > 1 else "settings.ini"
    if not os.path.exists(ini):
        print(f"INI-Datei nicht gefunden: {ini}", file=sys.stderr)
        sys.exit(1)
    app = SettingsApp(ini)
    sys.exit(app.run([]))
