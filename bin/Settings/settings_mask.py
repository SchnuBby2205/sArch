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
from gi.repository import Gtk, Adw, Gdk, Gio
import configparser, os, sys, re, json, copy


# ── Localisation ─────────────────────────────────────────────────────────────

import locale as _locale_mod

_STRINGS: dict = {}

def load_locale(locale_dir: str = None) -> None:
    """
    Loads UI strings from a locales/<lang>.ini file.
    Detection order:
      1. LANGUAGE / LANG environment variable
      2. System locale
      3. Fallback: English (en)
    """
    global _STRINGS

    if locale_dir is None:
        locale_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "locales")

    # Detect language
    lang = (os.environ.get("LANGUAGE") or
            os.environ.get("LANG") or
            _locale_mod.getlocale()[0] or "en")
    lang = lang.split("_")[0].split(".")[0].lower()  # "de_DE.UTF-8" → "de"

    # Try detected language, then fallback to English
    for try_lang in [lang, "en"]:
        path = os.path.join(locale_dir, f"{try_lang}.ini")
        if os.path.exists(path):
            cfg = configparser.ConfigParser()
            cfg.read(path, encoding="utf-8")
            if "ui" in cfg:
                _STRINGS = dict(cfg["ui"])
                return

def t(key: str, **kwargs) -> str:
    """Return a localised string, with optional {placeholder} substitution."""
    s = _STRINGS.get(key, key)
    if kwargs:
        for k, v in kwargs.items():
            s = s.replace("{" + k + "}", str(v))
    return s


# ── Localisation ─────────────────────────────────────────────────────────────

def _find_i18n_file(lang: str) -> str | None:
    """Searches for i18n/<lang>.ini relative to the script location."""
    base = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(base, "i18n", f"{lang}.ini")
    return path if os.path.exists(path) else None

def load_i18n(lang: str = "") -> dict:
    """
    Loads a localisation file from i18n/<lang>.ini.
    Falls back to en if the requested language is not found.
    Auto-detects system locale when lang is empty.
    """
    if not lang:
        import locale
        sys_lang = locale.getdefaultlocale()[0] or "en"
        lang = sys_lang.split("_")[0].lower()   # "de_DE" → "de"

    path = _find_i18n_file(lang)
    if not path:
        path = _find_i18n_file("en")
    if not path:
        return {}

    cfg = configparser.ConfigParser(interpolation=None)
    cfg.read(path, encoding="utf-8")
    result = {}
    for section in cfg.sections():
        for key, val in cfg[section].items():
            result[key] = val
    return result

# Global translation dict – populated in SettingsApp.__init__
_T: dict = {}

def t(key: str, **kwargs) -> str:
    """Return translated string, with optional {placeholder} substitution."""
    s = _T.get(key, key)
    if kwargs:
        try:
            s = s.format(**kwargs)
        except KeyError:
            pass
    return s


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
            "lua_func":     s.get("lua_func", ""),
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
        # hl.bind()
        if re.match(r'\s*hl\.bind\s*\(', line):
            indent   = len(line) - len(line.lstrip())
            new_line = " " * indent + _build_hl_bind(field_values) + "\n"
            lines[i] = new_line
            try:
                with open(config_file, "r+") as f:
                    f.seek(0); f.writelines(lines); f.truncate()
                return True
            except OSError: return False
        # hl.animation / hl.workspace_rule / hl.layer_rule (einzeilig)
        lm = re.match(r'\s*(hl\.(?:animation|workspace_rule|layer_rule))\s*\(', line)
        if lm:
            func     = lm.group(1)
            # field_defs aus entry holen (wird als __field_defs__ übergeben)
            fds      = field_values.pop("__field_defs__", [])
            indent   = len(line) - len(line.lstrip())
            new_line = " " * indent + _build_lua_func(func, field_values, fds) + "\n"
            lines[i] = new_line
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



# ── Animations ────────────────────────────────────────────────────────────────

def read_animations(config_file: str) -> list:
    """Liest alle hl.animation({...}) Einzeiler, gibt Liste von dicts zurück."""
    result = []
    if not config_file or not os.path.exists(config_file): return result
    pat = re.compile(r'hl\.animation\s*\(\{(.+)\}\)')
    try:
        with open(config_file) as f:
            lines = f.readlines()
        for i, line in enumerate(lines):
            if line.lstrip().startswith("--"): continue
            m = pat.search(line)
            if m:
                fields = _parse_inline_fields(m.group(1))
                fields["_line"] = i
                result.append(fields)
    except OSError: pass
    return result

def _parse_inline_fields(s: str) -> dict:
    """Parst 'key = val, key2 = val2' aus einem inline-Block."""
    result = {}
    for m in re.finditer(r'([\w_]+)\s*=\s*("(?:[^"\\]|\\.)*"|true|false|[\d.]+|[\w%]+)', s):
        result[m.group(1)] = m.group(2).strip()
    return result

def write_animation(config_file: str, line_idx: int, fields: dict) -> bool:
    """Schreibt eine hl.animation() Zeile neu."""
    try:
        with open(config_file) as f: lines = f.readlines()
        if line_idx >= len(lines): return False
        lines[line_idx] = _build_animation(fields) + "\n"
        with open(config_file, "r+") as f:
            f.seek(0); f.writelines(lines); f.truncate()
        return True
    except OSError: return False

def delete_line(config_file: str, line_idx: int) -> bool:
    """Löscht eine einzelne Zeile aus der Datei."""
    try:
        with open(config_file) as f: lines = f.readlines()
        if line_idx >= len(lines): return False
        del lines[line_idx]
        with open(config_file, "r+") as f:
            f.seek(0); f.writelines(lines); f.truncate()
        return True
    except OSError: return False

def _build_animation(fields: dict) -> str:
    skip = {"_line"}
    parts = []
    order = ["leaf","enabled","speed","bezier","spring","style"]
    seen  = set()
    for k in order:
        if k in fields and k not in skip:
            v = fields[k]
            # String-Werte in Anführungszeichen wenn kein bool/zahl
            if v not in ("true","false") and not re.match(r'^[\d.]+$', v):
                v = f'"{v}"'
            parts.append(f"{k} = {v}")
            seen.add(k)
    for k,v in fields.items():
        if k not in seen and k not in skip:
            if v not in ("true","false") and not re.match(r'^[\d.]+$', v):
                v = f'"{v}"'
            parts.append(f"{k} = {v}")
    return f'hl.animation({{ {", ".join(parts)} }})'

def append_animation(config_file: str, fields: dict) -> bool:
    try:
        with open(config_file, "a") as f:
            f.write(_build_animation(fields) + "\n")
        return True
    except OSError: return False


# ── Autostart ─────────────────────────────────────────────────────────────────

def read_autostarts(config_file: str) -> list:
    """Liest alle hl.exec_cmd(...) Zeilen innerhalb von hl.on(...)."""
    result = []
    if not config_file or not os.path.exists(config_file): return result
    pat = re.compile(r'hl\.exec_cmd\s*\((.+)\)')
    try:
        with open(config_file) as f: lines = f.readlines()
        for i, line in enumerate(lines):
            if line.lstrip().startswith("--"): continue
            m = pat.search(line)
            if m:
                cmd = m.group(1).strip()
                result.append({"cmd": cmd, "_line": i})
    except OSError: pass
    return result

def write_autostart(config_file: str, line_idx: int, cmd: str) -> bool:
    try:
        with open(config_file) as f: lines = f.readlines()
        if line_idx >= len(lines): return False
        indent = "    "
        lines[line_idx] = f'{indent}hl.exec_cmd({cmd})\n'
        with open(config_file, "r+") as f:
            f.seek(0); f.writelines(lines); f.truncate()
        return True
    except OSError: return False

def append_autostart(config_file: str, cmd: str) -> bool:
    """Fügt einen neuen hl.exec_cmd() vor end) ein."""
    try:
        with open(config_file) as f: lines = f.readlines()
        # Finde "end)" Zeile
        end_idx = None
        for i, l in enumerate(lines):
            if re.search(r'end\s*\)', l):
                end_idx = i
                break
        if end_idx is None:
            # Ans Ende hängen
            with open(config_file, "a") as f:
                f.write(f'    hl.exec_cmd({cmd})\n')
        else:
            lines.insert(end_idx, f'    hl.exec_cmd({cmd})\n')
            with open(config_file, "r+") as f:
                f.seek(0); f.writelines(lines); f.truncate()
        return True
    except OSError: return False


# ── Workspace Rules ───────────────────────────────────────────────────────────

def read_workspace_rules(config_file: str) -> list:
    """Liest alle hl.workspace_rule({...}) Einzeiler."""
    result = []
    if not config_file or not os.path.exists(config_file): return result
    pat = re.compile(r'hl\.workspace_rule\s*\(\{(.+)\}\)')
    try:
        with open(config_file) as f: lines = f.readlines()
        for i, line in enumerate(lines):
            if line.lstrip().startswith("--"): continue
            m = pat.search(line)
            if m:
                fields = _parse_inline_fields(m.group(1))
                fields["_line"] = i
                result.append(fields)
    except OSError: pass
    return result

def _build_workspace_rule(fields: dict) -> str:
    skip = {"_line"}
    order = ["workspace","default_name","monitor","layout","default"]
    parts = []
    seen  = set()
    for k in order:
        if k in fields and k not in skip:
            v = fields[k]
            if v not in ("true","false") and not re.match(r'^[\d.]+$', v):
                v = f'"{v}"'
            parts.append(f"{k} = {v}")
            seen.add(k)
    for k,v in fields.items():
        if k not in seen and k not in skip:
            if v not in ("true","false") and not re.match(r'^[\d.]+$', v):
                v = f'"{v}"'
            parts.append(f"{k} = {v}")
    return f'hl.workspace_rule({{ {", ".join(parts)} }})'

def write_workspace_rule(config_file: str, line_idx: int, fields: dict) -> bool:
    try:
        with open(config_file) as f: lines = f.readlines()
        if line_idx >= len(lines): return False
        lines[line_idx] = _build_workspace_rule(fields) + "\n"
        with open(config_file, "r+") as f:
            f.seek(0); f.writelines(lines); f.truncate()
        return True
    except OSError: return False

def append_workspace_rule(config_file: str, fields: dict) -> bool:
    try:
        with open(config_file, "a") as f:
            f.write(_build_workspace_rule(fields) + "\n")
        return True
    except OSError: return False


# ── Layer Rules ───────────────────────────────────────────────────────────────

def read_layer_rules(config_file: str) -> list:
    result = []
    if not config_file or not os.path.exists(config_file): return result
    pat = re.compile(r'hl\.layer_rule\s*\(\{(.+)\}\)')
    try:
        with open(config_file) as f: lines = f.readlines()
        for i, line in enumerate(lines):
            if line.lstrip().startswith("--"): continue
            m = pat.search(line)
            if m:
                fields = _parse_inline_fields(m.group(1))
                fields["_line"] = i
                result.append(fields)
    except OSError: pass
    return result

def _build_layer_rule(fields: dict) -> str:
    skip = {"_line"}
    name  = fields.get("name","")
    cls   = fields.get("class","")
    parts = [f'name = "{name}"']
    if cls: parts.append(f'match = {{ class = "{cls}" }}')
    for k,v in fields.items():
        if k not in skip | {"name","class","match"}:
            if v not in ("true","false") and not re.match(r'^[\d.]+$', v):
                v = f'"{v}"'
            parts.append(f"{k} = {v}")
    return f'hl.layer_rule({{ {", ".join(parts)} }})'

def write_layer_rule(config_file: str, line_idx: int, fields: dict) -> bool:
    try:
        with open(config_file) as f: lines = f.readlines()
        if line_idx >= len(lines): return False
        lines[line_idx] = _build_layer_rule(fields) + "\n"
        with open(config_file, "r+") as f:
            f.seek(0); f.writelines(lines); f.truncate()
        return True
    except OSError: return False

def append_layer_rule(config_file: str, fields: dict) -> bool:
    try:
        with open(config_file, "a") as f:
            f.write(_build_layer_rule(fields) + "\n")
        return True
    except OSError: return False

def _build_lua_func(func: str, fields: dict, field_defs: list) -> str:
    """
    Generischer Builder für einzeilige hl.xxx({...}) Calls.
    Felder mit "block": "name" werden als name = { key = val, ... } gruppiert.
    Mehrere Felder mit demselben block-Namen landen im selben Sub-Block.
    Schreibt nur Felder die nicht leer sind, in der Reihenfolge aus field_defs.
    """
    skip = {"_line"}

    def _fmt(v: str) -> str:
        if v in ("true", "false"): return v
        if re.match(r'^[\d.]+$', v): return v
        return f'"{v}"'

    # Alle block-Felder vorsammeln: {block_name: [(key, fmtval), ...]}
    blocks: dict = {}
    for fd in field_defs:
        blk = fd.get("block")
        if not blk: continue
        k = fd["key"]
        v = str(fields.get(k, "")).strip()
        if not v: continue
        blocks.setdefault(blk, []).append(f"{k} = {_fmt(v)}")

    # Ausgabe in field_defs Reihenfolge, Blöcke einmalig einfügen
    result_parts = []
    inserted_blocks: set = set()
    for fd in field_defs:
        k   = fd["key"]
        blk = fd.get("block")
        if k in skip: continue
        if blk:
            if blk not in inserted_blocks and blk in blocks:
                result_parts.append(f"{blk} = {{ {', '.join(blocks[blk])} }}")
                inserted_blocks.add(blk)
        else:
            v = str(fields.get(k, "")).strip()
            if not v: continue
            result_parts.append(f"{k} = {_fmt(v)}")

    return f'{func}({{ {", ".join(result_parts)} }})'



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
        elif template == "__lua_func__" and vals:
            func      = vals.pop("__lua_func__", "hl.unknown")
            field_defs = vals.pop("__field_defs__", [])
            text = _build_lua_func(func, vals, field_defs)
        else:
            text = template
        with open(config_file, "a") as f:
            f.write(text + "\n")
        return True
    except OSError: return False


# ── GTK4 / Adwaita App ────────────────────────────────────────────────────────

class SettingsApp(Adw.Application):
    def __init__(self, ini_path: str, lang: str = ""):
        super().__init__(application_id="de.local.settings-mask",
                         flags=Gio.ApplicationFlags.NON_UNIQUE)
        self.ini_path = ini_path
        self.category_pending: dict = {}
        self._all_categories: dict = {}
        global _T
        _T = load_i18n(lang)
        self.connect("activate", self.on_activate)

    def on_activate(self, app):
        self._all_categories = load_categories(self.ini_path)
        load_locale()
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
                if s["type"] in ("variable","animation","autostart","workspace_rule","layer_rule"):
                    self._add_special_group(outer_box, cat_name, s)
                    break
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
            else:
                ok = True

            if not ok:
                errors.append(f"{entry.get('config_key','?')} [{entry.get('index_value','')}] → {entry.get('config_file','')}")

        if errors:
            self._show_error_dialog(errors)
        else:
            toast = Adw.Toast(title=t("toast_applied", category=cat_name))
            toast.set_timeout(3)
            self._toast_overlay.add_toast(toast)

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
    args = parser.parse_args()
    if not os.path.exists(args.ini):
        print(f"INI file not found: {args.ini}", file=sys.stderr)
        sys.exit(1)
    app = SettingsApp(args.ini, lang=args.lang)
    sys.exit(app.run([]))