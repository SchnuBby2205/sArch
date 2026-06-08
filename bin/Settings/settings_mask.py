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
"""

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, Gdk
import configparser, os, sys, re, json, copy


# ── Matugen ───────────────────────────────────────────────────────────────────

MATUGEN_PATHS = [
    os.path.expanduser("~/.themes/Matugen/gtk-4.0/colors.css"),
    os.path.expanduser("~/.cache/matugen/colors.css"),
    os.path.expanduser("~/.config/matugen/colors.css"),
]

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
    provider = Gtk.CssProvider()
    provider.load_from_string(css)
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER)
    return True


# ── INI laden ─────────────────────────────────────────────────────────────────

def _parse_fields(s) -> list:
    """Liest fields = JSON aus der INI für keybind-Typ."""
    raw = s.get("fields", "")
    if not raw: return []
    try: return json.loads(raw)
    except Exception: return []

def load_categories(ini_path: str) -> dict:
    cfg = configparser.ConfigParser()
    cfg.read(ini_path)
    categories = {}
    for section in cfg.sections():
        s   = cfg[section]
        cat = s.get("category", "Allgemein")
        entry = {
            "label":        s.get("label", section),
            "description":  s.get("description", ""),
            "type":         s.get("type", "slider"),
            "options":      [o.strip() for o in s.get("options","").split(",") if o.strip()],
            "min":          float(s.get("min", 0)),
            "max":          float(s.get("max", 100)),
            "step":         float(s.get("step", 1)),
            "config_file":  s.get("config_file", ""),
            "config_key":   s.get("config_key", ""),
            "parent_key":   s.get("parent_key", ""),
            "index_field":  s.get("index_field", ""),
            "index_value":  s.get("index_value", ""),   # leer = alle auto-einlesen
            "format":       s.get("format", "lua"),
            # keybind / new_template
            "fields":       _parse_fields(s),
            "new_template": s.get("new_template", ""),  # Lua-Template für neuen Eintrag
            "append_file":  s.get("append_file", s.get("config_file","")),
            "visible":      s.get("visible", "true").lower() != "false",
        }
        categories.setdefault(cat, []).append(entry)
    return categories


# ── Block-Suche ───────────────────────────────────────────────────────────────

def _make_pattern(key: str) -> re.Pattern:
    return re.compile(r'(?<!\w)' + re.escape(key) + r'\s*=\s*')

def _read_str_after(line: str, pat: re.Pattern) -> str:
    """Extrahiert String-Wert nach einem Pattern in einer Zeile."""
    m = pat.search(line)
    if not m: return ""
    rest = line[m.end():].strip()
    sm = re.match(r'"([^"]*)"', rest)
    if sm: return sm.group(1)
    wm = re.match(r'([\w_@x.+:-]+)', rest)
    if wm: return wm.group(1)
    return ""

def _find_all_indexed_blocks(lines: list, index_field: str) -> list:
    """
    Findet alle Blöcke/Zeilen mit index_field und gibt Liste von
    (index_value, start, end) zurück.
    Unterstützt:
      - Mehrzeilige Blöcke: hl.window_rule({ name = "foo", ... })
      - Einzeilige Statements: hl.bind(..., { description = "foo" })
    """
    pat_field = _make_pattern(index_field)
    results   = []
    depth     = 0
    blk_start = None
    idx_val   = None

    for i, line in enumerate(lines):
        if line.lstrip().startswith("--"): continue
        opens  = line.count("{") + line.count("(")
        closes = line.count("}") + line.count(")")

        if blk_start is None and opens > 0:
            blk_start = i
            depth     = opens - closes
            idx_val   = None

        if blk_start is not None:
            # index_field auf dieser Zeile suchen (auch Einzeiler)
            m = pat_field.search(line)
            if m and idx_val is None:
                idx_val = _read_str_after(line, pat_field)
            # Tiefe für Folgezeilen aktualisieren (erste Zeile schon oben gezählt)
            if i > blk_start:
                depth += opens - closes

        # Block endet wenn depth <= 0 (nach idx_val-Suche)
        if blk_start is not None and depth <= 0:
            if idx_val:
                results.append((idx_val, blk_start, i))
            blk_start = None
            idx_val   = None
            depth     = 0

    return results

def _find_indexed_block(lines: list, index_field: str, index_value: str) -> tuple:
    for val, s, e in _find_all_indexed_blocks(lines, index_field):
        if val == index_value:
            return s, e
    return 0, len(lines)-1

def _find_parent_block(lines: list, parent_key: str) -> tuple:
    if not parent_key: return 0, len(lines)-1
    start = None; depth = 0
    pat = re.compile(r'(?<!\w)' + re.escape(parent_key) + r'\s*=\s*\{')
    for i, line in enumerate(lines):
        if line.lstrip().startswith("--"): continue
        if start is None:
            if pat.search(line):
                start = i
                depth = line.count("{")-line.count("}")
        else:
            depth += line.count("{")-line.count("}")
            if depth <= 0: return start, i
    return (start or 0), len(lines)-1

def _get_search_range(lines: list, entry: dict) -> tuple:
    if entry.get("index_field") and entry.get("index_value"):
        return _find_indexed_block(lines, entry["index_field"], entry["index_value"])
    elif entry.get("parent_key"):
        return _find_parent_block(lines, entry["parent_key"])
    else:
        return 0, len(lines)-1


# ── Werte lesen ───────────────────────────────────────────────────────────────

def read_current_value(config_file: str, entry: dict, fallback: float) -> float:
    if not config_file or not os.path.exists(config_file): return fallback
    pattern = _make_pattern(entry["config_key"])
    num_pat = re.compile(r'([\d.+-]+)')
    try:
        with open(config_file) as f: lines = f.readlines()
        start, end = _get_search_range(lines, entry)
        for line in lines[start:end+1]:
            if line.lstrip().startswith("--"): continue
            m = pattern.search(line)
            if m:
                nm = num_pat.search(line[m.end():])
                if nm: return float(nm.group(1))
    except (OSError, ValueError): pass
    return fallback

def read_current_string(config_file: str, entry: dict, fallback: str) -> str:
    if not config_file or not os.path.exists(config_file): return fallback
    pattern = _make_pattern(entry["config_key"])
    try:
        with open(config_file) as f: lines = f.readlines()
        start, end = _get_search_range(lines, entry)
        for line in lines[start:end+1]:
            if line.lstrip().startswith("--"): continue
            if pattern.search(line):
                return _read_str_after(line, pattern)
    except OSError: pass
    return fallback

def _parse_hl_bind(line: str) -> dict:
    """
    Parst eine hl.bind()-Zeile und gibt die Felder als Dict zurück.
    Format: hl.bind(KEYBIND, COMMAND(ARG), { description = "..." })
    """
    result = {"use_mainmod": "no", "modifier": "none", "key": "",
              "command": "", "argument": "", "description": ""}
    m = re.match(r'hl\.bind\s*\(', line)
    if not m: return result
    inner = line[m.end():]

    known_mods = {"CTRL","ALT","SHIFT","SUPER","HYPER","META"}

    if "mainMod" in inner:
        result["use_mainmod"] = "yes"
        mm = re.search(r'mainMod\s*\.\.\s*"\s*\+\s*([^"]*)"\s*,', inner)
        if mm:
            parts = [p.strip() for p in mm.group(1).split("+") if p.strip()]
            mods  = [p for p in parts if p.upper() in known_mods]
            keys  = [p for p in parts if p.upper() not in known_mods]
            result["modifier"] = mods[0] if mods else "none"
            result["key"]      = keys[0] if keys else ""
    else:
        km = re.match(r'\s*"([^"]+)"\s*,', inner)
        if km:
            parts = [p.strip() for p in km.group(1).split("+") if p.strip()]
            mods  = [p for p in parts if p.upper() in known_mods]
            keys  = [p for p in parts if p.upper() not in known_mods]
            result["modifier"] = mods[0] if mods else "none"
            result["key"]      = keys[0] if keys else ""

    # Befehl: hl.dsp.xxx( – auch Punkte im Namen erlaubt (window.close)
    cm = re.search(r'(hl\.dsp\.[\w.]+)\s*\(', inner)
    if cm:
        result["command"] = cm.group(1)
        arg_start = cm.end()
        arg_inner = inner[arg_start:]
        # Nur bis zum ersten ) lesen – das ist das Ende der Befehlsklammer
        close = arg_inner.find(")")
        if close > 0:
            arg_str = arg_inner[:close].strip()
            result["argument"] = arg_str
        # close == 0: leere Klammern, Argument bleibt ""

    # description aus { description = "..." }
    desc_m = re.search(r'description\s*=\s*"([^"]*)"', inner)
    if desc_m:
        result["description"] = desc_m.group(1)

    return result


def read_keybind_fields(config_file: str, entry: dict) -> dict:
    """
    Liest Keybind-Felder aus der Datei.
    Für hl.bind()-Zeilen: spezieller Parser.
    Für Block-Felder (window_rule etc.): key=value Suche.
    """
    result = {}
    if not config_file or not os.path.exists(config_file): return result
    try:
        with open(config_file) as f: lines = f.readlines()
        start, end = _get_search_range(lines, entry)

        # Prüfe ob der Block eine hl.bind()-Zeile enthält
        for line in lines[start:end+1]:
            if line.lstrip().startswith("--"): continue
            if re.match(r'\s*hl\.bind\s*\(', line):
                return _parse_hl_bind(line.strip())

        # Fallback: key=value Suche für Block-Einträge (window_rule etc.)
        for field in entry.get("fields", []):
            key = field.get("key","")
            if not key: continue
            pat = _make_pattern(key)
            for line in lines[start:end+1]:
                if line.lstrip().startswith("--"): continue
                if pat.search(line):
                    result[key] = _read_str_after(line, pat)
                    break
    except OSError: pass
    return result


# ── Wert schreiben ────────────────────────────────────────────────────────────

def write_value(config_file: str, entry: dict, value) -> bool:
    if not config_file: return False
    try:
        with open(config_file) as f: lines = f.readlines()
    except OSError: return False

    start, end = _get_search_range(lines, entry)
    pattern    = _make_pattern(entry["config_key"])
    fmt        = entry["format"]
    replaced   = False

    for i in range(start, end+1):
        line = lines[i]
        if line.lstrip().startswith("--"): continue
        m = pattern.search(line)
        if m:
            before = line[:m.end()]
            after  = line[m.end():]
            if fmt == "lua_string":
                new_after = re.sub(r'"[^"]*"', f'"{value}"', after, count=1)
                if new_after == after:
                    new_after = re.sub(r'[\w_@x.+:-]+', str(value), after, count=1)
            else:
                new_after = re.sub(r'[\d.+-]+', str(int(value)), after, count=1)
            lines[i] = before + new_after
            replaced = True
            break

    if not replaced:
        print(f"WARN: '{entry['config_key']}' "
              f"(idx={entry.get('index_value','')}) nicht gefunden in {config_file}", flush=True)
        return False

    try:
        with open(config_file, "r+") as f:
            f.seek(0); f.writelines(lines); f.truncate()
        return True
    except OSError: return False

def _build_hl_bind(fv: dict) -> str:
    """Baut eine hl.bind()-Zeile aus den Feldwerten neu auf."""
    use_mm  = fv.get("use_mainmod", "no") == "yes"
    mod     = fv.get("modifier", "none")
    key     = fv.get("key", "")
    command = fv.get("command", "hl.dsp.exec_cmd")
    arg     = fv.get("argument", "")
    desc    = fv.get("description", "")

    # Keybind-String zusammenbauen
    key_parts = []
    if mod and mod != "none":
        key_parts.append(mod)
    if key:
        key_parts.append(key)
    key_str = " + ".join(key_parts)

    if use_mm:
        bind_key = f'mainMod .. " + {key_str}"' if key_str else 'mainMod'
    else:
        bind_key = f'"{key_str}"'

    # Befehl mit Argument
    if arg:
        cmd_str = f'{command}({arg})'
    else:
        cmd_str = f'{command}()'

    # description anhängen wenn vorhanden
    if desc:
        return f'hl.bind({bind_key}, {cmd_str}, {{ description = "{desc}" }})'
    else:
        return f'hl.bind({bind_key}, {cmd_str})'


def write_keybind_fields(config_file: str, entry: dict, field_values: dict) -> bool:
    """
    Schreibt Keybind-Felder zurück in die Datei.
    Für hl.bind()-Zeilen: baut die ganze Zeile neu auf.
    Für Block-Einträge (window_rule etc.): key=value Suche.
    """
    if not config_file: return False
    try:
        with open(config_file) as f: lines = f.readlines()
    except OSError: return False

    start, end = _get_search_range(lines, entry)

    # Prüfe ob es eine hl.bind()-Zeile ist
    for i in range(start, end+1):
        line = lines[i]
        if line.lstrip().startswith("--"): continue
        if re.match(r'\s*hl\.bind\s*\(', line):
            indent    = len(line) - len(line.lstrip())
            new_line  = " " * indent + _build_hl_bind(field_values) + "\n"
            lines[i]  = new_line
            try:
                with open(config_file, "r+") as f:
                    f.seek(0); f.writelines(lines); f.truncate()
                return True
            except OSError: return False

    # Block-Einträge (hl.window_rule / hl.layer_rule):
    # Ganzen Block neu aufbauen analog zu _build_hl_bind
    block_lines = lines[start:end+1]
    block_text  = "".join(block_lines)

    # Einrückung der ersten Zeile merken
    indent = " " * (len(block_lines[0]) - len(block_lines[0].lstrip()))

    # Prüfe welche Funktion verwendet wird (window_rule oder layer_rule)
    func_m = re.search(r'hl\.(\w+_rule)\s*\(', block_text)
    func   = func_m.group(1) if func_m else "window_rule"

    # Felder aus field_values lesen
    name      = field_values.get("name", "")
    cls       = field_values.get("class", "").strip()
    title     = field_values.get("title", "").strip()
    workspace = field_values.get("workspace", "").strip()
    flt       = field_values.get("float", "").strip()
    center    = field_values.get("center", "").strip()
    fullscr   = field_values.get("fullscreen", "").strip()

    # match-Block aufbauen
    match_parts = []
    if cls:       match_parts.append(f'class = "{cls}"')
    if title:     match_parts.append(f'title = "{title}"')
    if workspace and not cls and not title:
        match_parts.append(f'workspace = "{workspace}"')
    match_str = ", ".join(match_parts)

    # Neuen Block zusammensetzen
    # Felder sammeln
    fields_out = [f'name = "{name}"']
    if match_str:
        fields_out.append(f"match = {{ {match_str} }}")
    if workspace and (cls or title):
        fields_out.append(f'workspace = "{workspace}"')
    for key, val in [("float", flt), ("center", center), ("fullscreen", fullscr)]:
        if val and val not in ("", "none"):
            fields_out.append(f"{key} = {val}")
    # Unbekannte Felder aus Originalblock übernehmen (z.B. opacity, blur)
    skip_keys = {"name", "match", "workspace", "float", "center", "fullscreen",
                 "class", "title"}
    for bl in block_lines:
        stripped = bl.strip().rstrip(",")
        km = re.match(r'([\w_]+)\s*=\s*(.+)', stripped)
        if km and km.group(1) not in skip_keys and not bl.lstrip().startswith("--"):
            k = km.group(1)
            v = field_values.get(k, km.group(2).strip().rstrip(","))
            fields_out.append(f"{k} = {v}")
    inner = ", ".join(fields_out)
    new_block = [f"hl.{func}({{ {inner} }})\n"]
    lines[start:end+1] = new_block

    try:
        with open(config_file, "r+") as f:
            f.seek(0); f.writelines(lines); f.truncate()
        return True
    except OSError: return False

def read_variables(config_file: str) -> list:
    """Liest alle VAR = VALUE Zeilen, gibt [(name, value, line_index)] zurück."""
    result = []
    if not config_file or not os.path.exists(config_file): return result
    try:
        with open(config_file) as f:
            lines = f.readlines()
        for i, line in enumerate(lines):
            stripped = line.strip()
            if stripped.startswith("--") or not stripped: continue
            m = re.match(r'([\w_]+)\s*=\s*(.+)', stripped)
            if m:
                result.append((m.group(1), m.group(2).strip().rstrip(","), i))
    except OSError: pass
    return result

def write_variable(config_file: str, line_index: int, name: str, value: str) -> bool:
    """Überschreibt eine Variable in der Datei – Wert exakt wie eingegeben."""
    try:
        with open(config_file) as f: lines = f.readlines()
        if line_index >= len(lines): return False
        # Original-Einrückung beibehalten
        orig  = lines[line_index]
        indent = orig[:len(orig) - len(orig.lstrip())]
        lines[line_index] = f"{indent}{name} = {value}\n"
        with open(config_file, "r+") as f:
            f.seek(0); f.writelines(lines); f.truncate()
        return True
    except OSError: return False

def delete_variable(config_file: str, line_index: int) -> bool:
    """Löscht eine Variablen-Zeile aus der Datei."""
    try:
        with open(config_file) as f: lines = f.readlines()
        if line_index >= len(lines): return False
        del lines[line_index]
        with open(config_file, "r+") as f:
            f.seek(0); f.writelines(lines); f.truncate()
        return True
    except OSError: return False

def append_variable(config_file: str, name: str, value: str) -> bool:
    """Hängt eine neue Variable ans Ende der Datei."""
    try:
        with open(config_file, "a") as f:
            f.write(f"{name} = {value}\n")
        return True
    except OSError: return False


def delete_entry(config_file: str, entry: dict) -> bool:
    """
    Löscht den Block/die Zeile die durch index_field/index_value identifiziert wird.
    Für hl.bind()-Einzeiler: genau diese Zeile löschen.
    Für mehrzeilige Blöcke (window_rule): start bis end löschen.
    """
    if not config_file: return False
    try:
        with open(config_file) as f: lines = f.readlines()
    except OSError: return False

    start, end = _get_search_range(lines, entry)
    if start == 0 and end == len(lines)-1 and not entry.get("index_value"):
        print("WARN: delete_entry – kein spezifischer Block gefunden", flush=True)
        return False

    # Leere Zeilen direkt vor dem Block mitentfernen
    while start > 0 and lines[start-1].strip() == "":
        start -= 1
    # Leere Zeilen direkt nach dem Block mitentfernen
    after = end + 1
    while after < len(lines) and lines[after].strip() == "":
        after += 1

    del lines[start:after]

    try:
        with open(config_file, "r+") as f:
            f.seek(0); f.writelines(lines); f.truncate()
        return True
    except OSError: return False


def _build_windowrule(vals: dict) -> str:
    name      = vals.get("name", "")
    cls       = vals.get("class", "").strip()
    title     = vals.get("title", "").strip()
    workspace = vals.get("workspace", "").strip()
    match_parts = []
    if cls:   match_parts.append(f'class = "{cls}"')
    if title: match_parts.append(f'title = "{title}"')
    if workspace and not cls and not title:
        match_parts.append(f'workspace = "{workspace}"')
    match_str = ", ".join(match_parts)
    fields = [f'name = "{name}"']
    if match_str: fields.append(f"match = {{ {match_str} }}")
    if workspace and (cls or title): fields.append(f'workspace = "{workspace}"')
    for key in ("float", "center", "fullscreen"):
        v = vals.get(key, "").strip()
        if v and v not in ("", "none"): fields.append(f"{key} = {v}")
    return f'hl.window_rule({{ {", ".join(fields)} }})'

def append_new_entry(config_file: str, template: str, vals: dict = None) -> bool:
    """Hängt einen neuen Eintrag ans Ende der Datei."""
    if not config_file or not template: return False
    try:
        if template == "__windowrule__" and vals:
            text = _build_windowrule(vals)
        elif template == "__keybind__" and vals:
            text = _build_hl_bind(vals)
        else:
            text = template
        with open(config_file, "a") as f:
            f.write(text + "\n")
        return True
    except OSError: return False


# ── GTK4 / Adwaita App ────────────────────────────────────────────────────────

class SettingsApp(Adw.Application):
    def __init__(self, ini_path: str):
        super().__init__(application_id="de.local.settings-mask")
        self.ini_path = ini_path
        self.category_pending: dict = {}
        self._all_categories: dict = {}
        self.connect("activate", self.on_activate)

    def on_activate(self, app):
        self._all_categories = load_categories(self.ini_path)
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK)
        apply_matugen_theme()

        win = Adw.ApplicationWindow(application=app)
        win.set_title("Einstellungen")
        win.set_default_size(780, 560)
        self._win = win
        self._toast_overlay = Adw.ToastOverlay()

        split = Adw.NavigationSplitView()
        split.set_min_sidebar_width(180)
        split.set_max_sidebar_width(240)

        # ── Sidebar ───────────────────────────────────────────────────────────
        sidebar_page    = Adw.NavigationPage(title="Kategorien")
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
        self._content_page    = Adw.NavigationPage(title="Einstellungen")
        self._content_toolbar = Adw.ToolbarView()
        self._content_toolbar.add_top_bar(Adw.HeaderBar())
        self._content_page.set_child(self._content_toolbar)
        split.set_content(self._content_page)

        self._category_widgets: dict = {}
        self._build_all_categories()

        first = self._sidebar_list.get_row_at_index(0)
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
            pref_group = Adw.PreferencesGroup()
            pref_group.set_title(grp_title if grp_title != "__default__" else cat_name)
            pref_group.set_description('Werte anpassen und mit "Übernehmen" bestätigen.')

            # + Button in Header wenn new_template vorhanden
            if has_new_template and grp_title == list(groups.keys())[0]:
                add_btn = Gtk.Button()
                add_btn.set_icon_name("list-add-symbolic")
                add_btn.add_css_class("flat")
                add_btn.set_tooltip_text("Neuen Eintrag anlegen")
                add_btn.connect("clicked", self._on_new_entry, cat_name, settings)
                pref_group.set_header_suffix(add_btn)

            for s in entries:
                if s["type"] == "variable":
                    self._add_variable_group(outer_box, cat_name, s)
                    break  # variable-Typ baut eigene Gruppe
                elif s["type"] == "multisetting":
                    self._add_keybind(pref_group, cat_name, s)
                elif s["type"] == "dropdown":
                    self._add_dropdown(pref_group, cat_name, s)
                else:
                    self._add_slider(pref_group, cat_name, s)

            outer_box.append(pref_group)
            outer_box.append(Gtk.Separator())

        # Buttons
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        btn_box.set_halign(Gtk.Align.END); btn_box.set_margin_top(4)
        reset_btn = Gtk.Button(label="Zurücksetzen")
        reset_btn.add_css_class("flat")
        reset_btn.connect("clicked", self._on_reset, cat_name)
        apply_btn = Gtk.Button(label="Übernehmen")
        apply_btn.add_css_class("suggested-action")
        apply_btn.connect("clicked", self._on_apply, cat_name)
        btn_box.append(reset_btn); btn_box.append(apply_btn)
        outer_box.append(btn_box)

        clamp.set_child(outer_box)
        scroll.set_child(clamp)
        return scroll

    # ── Slider ────────────────────────────────────────────────────────────────

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
        add_btn.set_tooltip_text("Neue Variable anlegen")
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
            del_btn.set_tooltip_text("Variable löschen")

            def make_del(cfg, lidx, r, cat, ob, sv):
                def cb(_):
                    dialog = Adw.AlertDialog(
                        heading="Wirklich löschen?",
                        body=f"Variable \"{r.get_title()}\" wird entfernt.",
                    )
                    dialog.add_response("cancel", "Abbrechen")
                    dialog.add_response("delete", "Löschen")
                    dialog.set_response_appearance("delete", Adw.ResponseAppearance.DESTRUCTIVE)
                    dialog.set_default_response("cancel")
                    def on_resp(d, resp):
                        if resp != "delete": return
                        if delete_variable(cfg, lidx):
                            self._rebuild_variable_page(cat, ob, sv)
                            toast = Adw.Toast(title="Variable gelöscht.")
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

    def _rebuild_variable_page(self, cat_name: str, outer_box: Gtk.Box, s: dict):
        """Baut die Variable-Seite neu auf."""
        # outer_box leeren
        child = outer_box.get_first_child()
        while child:
            nxt = child.get_next_sibling()
            outer_box.remove(child)
            child = nxt
        self.category_pending[cat_name] = {}
        # Neu aufbauen
        self._add_variable_group(outer_box, cat_name, s)
        # Buttons wieder hinzufügen
        btn_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        btn_box.set_halign(Gtk.Align.END); btn_box.set_margin_top(4)
        reset_btn = Gtk.Button(label="Zurücksetzen")
        reset_btn.add_css_class("flat")
        reset_btn.connect("clicked", self._on_reset, cat_name)
        apply_btn = Gtk.Button(label="Übernehmen")
        apply_btn.add_css_class("suggested-action")
        apply_btn.connect("clicked", self._on_apply, cat_name)
        btn_box.append(reset_btn); btn_box.append(apply_btn)
        outer_box.append(btn_box)

    def _on_new_variable(self, _btn, cat_name: str, config_file: str,
                         outer_box: Gtk.Box, s: dict):
        """Dialog zum Anlegen einer neuen Variable."""
        dialog = Adw.AlertDialog(heading="Neue Variable", body="Name und Wert eingeben.")
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        box.set_margin_top(8); box.set_size_request(360, -1)
        name_entry  = Gtk.Entry(); name_entry.set_placeholder_text("Name (z.B. terminal)")
        value_entry = Gtk.Entry(); value_entry.set_placeholder_text('Wert (z.B. "kitty")')
        lbl_n = Gtk.Label(label="Name"); lbl_n.set_halign(Gtk.Align.START); lbl_n.add_css_class("dim-label")
        lbl_v = Gtk.Label(label="Wert"); lbl_v.set_halign(Gtk.Align.START); lbl_v.add_css_class("dim-label")
        box.append(lbl_n); box.append(name_entry)
        box.append(lbl_v); box.append(value_entry)
        dialog.set_extra_child(box)
        dialog.add_response("cancel", "Abbrechen")
        dialog.add_response("create", "Anlegen")
        dialog.set_default_response("create")
        dialog.set_response_appearance("create", Adw.ResponseAppearance.SUGGESTED)
        def on_resp(d, resp):
            if resp != "create": return
            n = name_entry.get_text().strip()
            v = value_entry.get_text().strip()
            if not n or not v: return
            if append_variable(config_file, n, v):
                self._rebuild_variable_page(cat_name, outer_box, s)
                toast = Adw.Toast(title=f"Variable \"{n}\" angelegt.")
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

        for field in fields:
            fkey   = field.get("key","")
            flabel = field.get("label", fkey)
            ftype  = field.get("type","text")
            fopts  = field.get("options", [])
            fval   = current_vals.get(fkey, fopts[0] if fopts else "")

            if ftype == "dropdown":
                # Wenn gelesener Wert nicht in options: vorne einfügen
                effective_opts = list(fopts)
                if fval and fval not in effective_opts:
                    effective_opts.insert(0, fval)
                fidx  = effective_opts.index(fval) if fval in effective_opts else 0
                combo = Adw.ComboRow()
                combo.set_title(flabel)
                combo.set_model(Gtk.StringList.new(effective_opts))
                combo.set_selected(fidx)
                exp_row.add_row(combo)
                widgets[fkey] = ("dropdown", combo, effective_opts)
            else:
                text_row = Adw.EntryRow()
                text_row.set_title(flabel)
                text_row.set_text(str(fval))
                exp_row.add_row(text_row)
                widgets[fkey] = ("text", text_row, [])

        # Mülltonne-Button als Suffix im ExpanderRow-Header
        del_btn = Gtk.Button()
        del_btn.set_icon_name("user-trash-symbolic")
        del_btn.add_css_class("flat")
        del_btn.add_css_class("destructive-action")
        del_btn.set_tooltip_text("Eintrag löschen")
        del_btn.set_valign(Gtk.Align.CENTER)

        # Closure für delete-Callback
        def make_del_cb(entry_s, cat, grp, row):
            def cb(_btn):
                dialog = Adw.AlertDialog(
                    heading="Wirklich löschen?",
                    body=f"\"{row.get_title()}\" wird dauerhaft aus der Datei entfernt.",
                )
                dialog.add_response("cancel", "Abbrechen")
                dialog.add_response("delete", "Löschen")
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
                        toast = Adw.Toast(title="Eintrag gelöscht.")
                        toast.set_timeout(3)
                        self._toast_overlay.add_toast(toast)
                    else:
                        self._show_error_dialog([f"Löschen fehlgeschlagen: {entry_s['config_file']}"])
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

        uid = f"multisetting|{s['config_file']}|{s.get('index_value','')}|{fkey}"
        self.category_pending[cat_name][uid] = {
            "type":"multisetting", "widgets":widgets, "fields":fields,
            "config_file":s["config_file"], "config_key":s["config_key"],
            "parent_key":s["parent_key"], "index_field":s["index_field"],
            "index_value":s["index_value"], "format":s["format"],
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
            heading="Neuen Eintrag anlegen",
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
        dialog.add_response("cancel", "Abbrechen")
        dialog.add_response("create", "Anlegen")
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

            filled = filled.replace("\\n", "\n")  # \n in INI → echte Newline
            ok = append_new_entry(tmpl_entry["append_file"], filled, vals={k: (fopts[w.get_selected()] if ft=="dropdown" else w.get_text()) for k,(ft,w,fopts) in field_widgets.items()})
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
                toast = Adw.Toast(title="Neuer Eintrag angelegt.")
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
                toast = Adw.Toast(title="Neuer Eintrag angelegt.")
                toast.set_timeout(3)
                self._toast_overlay.add_toast(toast)
            else:
                self._show_error_dialog([f"Konnte nicht schreiben: {tmpl_entry['append_file']}"])

        dialog.present(self._win)

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
            elif entry["type"] == "variable":
                entry["entry"].set_text(entry["original"])
            # keybind: kein Reset implementiert (komplex, später erweiterbar)

    def _on_apply(self, _btn, cat_name: str):
        errors = []
        for entry in self.category_pending.get(cat_name, {}).values():
            if entry["type"] == "slider":
                step = entry["scale"].get_adjustment().get_step_increment()
                raw  = entry["scale"].get_value()
                val  = round(raw/step)*step if step>0 else raw
                ok   = write_value(entry["config_file"], entry, val)
                if ok: entry["original"] = val

            elif entry["type"] == "dropdown":
                idx = entry["combo"].get_selected()
                val = entry["options"][idx] if idx < len(entry["options"]) else ""
                ok  = write_value(entry["config_file"], entry, val)
                if ok: entry["original"] = idx

            elif entry["type"] == "multisetting":
                fvals = {}
                for fkey, (ftype, widget, fopts) in entry["widgets"].items():
                    if ftype == "dropdown":
                        idx = widget.get_selected()
                        fvals[fkey] = fopts[idx] if idx < len(fopts) else ""
                    else:
                        fvals[fkey] = widget.get_text()
                ok = write_keybind_fields(entry["config_file"], entry, fvals)

            elif entry["type"] == "variable":
                val = entry["entry"].get_text()
                ok  = write_variable(
                    entry["config_file"], entry["line_idx"],
                    entry["var_name"], val
                )
                if ok: entry["original"] = val
            else:
                ok = True

            if not ok:
                errors.append(f"{entry.get('config_key','?')} [{entry.get('index_value','')}] → {entry.get('config_file','')}")

        if errors:
            self._show_error_dialog(errors)
        else:
            toast = Adw.Toast(title=f'"{cat_name}" erfolgreich übernommen.')
            toast.set_timeout(3)
            self._toast_overlay.add_toast(toast)

    def _show_error_dialog(self, failed: list):
        body = ("Folgende Einstellungen konnten nicht gespeichert werden:\n\n"
                + "\n".join(f"• {e}" for e in failed)
                + "\n\nBitte Dateipfade und Berechtigungen prüfen.")
        dialog = Adw.AlertDialog(heading="Fehler beim Schreiben", body=body)
        dialog.add_response("ok", "OK")
        dialog.set_default_response("ok")
        dialog.present(self._win)


# ── Entry Point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    ini = sys.argv[1] if len(sys.argv) > 1 else "settings.ini"
    if not os.path.exists(ini):
        print(f"INI-Datei nicht gefunden: {ini}", file=sys.stderr)
        sys.exit(1)
    app = SettingsApp(ini)
    sys.exit(app.run([]))