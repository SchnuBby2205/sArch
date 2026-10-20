#!/usr/bin/env python3
"""
settings_core.py – GUI-unabhängige Logik für die sArch-Einstellungen.

Wird von settings_backend.py (Quickshell-Frontend, JSON-CLI) und von der
alten GTK-Maske settings_mask.py gemeinsam verwendet:
  - INI laden (Kategorien / Feldtypen)
  - Hyprland-Lua lesen & schreiben (Werte, Keybinds, Rules, Variablen, Autostart, Animationen)
  - Hintergrundbild (matugen, Thumbnails), Schriften (Dunst/Rofi/kitty)
"""

import configparser, os, sys, re, json, copy
import subprocess, shlex, shutil, tempfile


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
            "config_file":  os.path.expanduser(s.get("config_file", "")),
            "config_key":   s.get("config_key", ""),
            "parent_key":   s.get("parent_key", ""),
            "index_field":  s.get("index_field", ""),
            "index_value":  s.get("index_value", ""),   # leer = alle auto-einlesen
            "format":       s.get("format", "lua"),
            # keybind / new_template
            "fields":       _parse_fields(s),
            "new_template": s.get("new_template", ""),  # Lua-Template für neuen Eintrag
            "append_file":  os.path.expanduser(s.get("append_file", s.get("config_file",""))),
            "visible":      s.get("visible", "true").lower() != "false",
            "lua_func":     s.get("lua_func", ""),
            # sArch-Erweiterungen
            "section":      section,
            "mirror_files": [os.path.expanduser(f.strip()) for f in s.get("mirror_files","").split(",") if f.strip()],
            "on_apply":     s.get("on_apply", ""),
            "extra":        dict(s),     # zusätzliche Keys für eigene Typen (wallpaper, fonts)
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
        # Lua-Kontrollstrukturen nicht als Blockstart werten
        if re.match(r'^\s*(for|while|if|elseif|else|do|repeat|until|end|local)\b', line): continue
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
        # Klammertiefe zählen um korrekte schliessende ) zu finden
        # Nötig für Argumente mit eingebetteten () z.B. $(date +%Y-%m-%d)
        depth_p = 0
        close   = -1
        in_str  = False
        str_ch  = None
        for ci, ch in enumerate(arg_inner):
            if in_str:
                if ch == str_ch and (ci == 0 or arg_inner[ci-1] != "\\"):
                    in_str = False
            elif ch in ('"', "'"):
                in_str = True
                str_ch = ch
            elif ch == "(":
                depth_p += 1
            elif ch == ")":
                if depth_p == 0:
                    close = ci
                    break
                depth_p -= 1
        if close > 0:
            result["argument"] = arg_inner[:close].strip()
        # close == 0 oder -1: leere Klammern, Argument bleibt ""

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

def _append_text(path: str, text: str):
    """Hängt text an – sorgt dafür, dass er in einer eigenen Zeile landet,
    auch wenn die Datei nicht mit einem Zeilenumbruch endet."""
    prefix = ""
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            if f.tell() > 0:
                f.seek(-1, 2)
                if f.read(1) != b"\n":
                    prefix = "\n"
    except OSError:
        pass
    with open(path, "a") as f:
        f.write(prefix + text)


def append_variable(config_file: str, name: str, value: str) -> bool:
    """Hängt eine neue Variable ans Ende der Datei."""
    try:
        _append_text(config_file, f"{name} = {value}\n")
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
        _append_text(config_file, _build_animation(fields) + "\n")
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
            _append_text(config_file, f'    hl.exec_cmd({cmd})\n')
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
        _append_text(config_file, _build_workspace_rule(fields) + "\n")
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
        _append_text(config_file, _build_layer_rule(fields) + "\n")
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
        _append_text(config_file, text + "\n")
        return True
    except OSError: return False


# ── sArch: Hintergrundbild / Schriften (ersetzt bin/sarch_*.sh) ─────────────────

SARCH_STATE_FILE = os.path.expanduser("~/.cache/sArch/current_wallpaper")
WP_EXTS = (".jpg", ".jpeg", ".png")

def _x(p: str) -> str:
    return os.path.expanduser(p.strip()) if p else p

def _split_paths(s: str) -> list:
    return [_x(p) for p in (s or "").split(",") if p.strip()]

def _spawn(cmd: list):
    """Startet einen Befehl im Hintergrund, Fehler (z.B. Programm fehlt) werden ignoriert."""
    try:
        subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        pass

def _notify(category: str, summary: str):
    _spawn(["dunstify", "-a", "Themes", "-u", "low", "-t", "1000", "-c", category, summary])

def _contrast(hex_col: str) -> str:
    r, g, b = int(hex_col[1:3], 16), int(hex_col[3:5], 16), int(hex_col[5:7], 16)
    return "#1a1a1a" if (0.299*r + 0.587*g + 0.114*b) > 140 else "#ffffff"

def _fmt_size(v: float) -> str:
    return f"{v:g}"

# ── Hintergrundbild ──

def list_wallpapers(wp_dir: str) -> list:
    try:
        names = sorted(os.listdir(wp_dir), key=str.lower)
    except OSError:
        return []
    return [os.path.join(wp_dir, n) for n in names
            if n.lower().endswith(WP_EXTS) and os.path.isfile(os.path.join(wp_dir, n))]

def thumb_path(cache_dir: str, wp: str) -> str:
    return os.path.join(cache_dir, os.path.basename(wp))

def ensure_thumbnails(wp_dir: str, cache_dir: str, size: int = 100) -> int:
    """Erzeugt fehlende/veraltete Vorschaubilder (wie früher sarch_create_thumbnails.sh)."""
    os.makedirs(cache_dir, exist_ok=True)
    made = 0
    for wp in list_wallpapers(wp_dir):
        th = thumb_path(cache_dir, wp)
        try:
            if os.path.exists(th) and os.path.getmtime(th) >= os.path.getmtime(wp):
                continue
            r = subprocess.run(["magick", wp, "-thumbnail", f"{size}x{size}^", "-gravity", "center",
                                "-extent", f"{size}x{size}", "-quality", "75", th],
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=60)
            if r.returncode == 0:
                made += 1
        except (OSError, subprocess.SubprocessError):
            pass
    return made

def read_current_wallpaper() -> tuple:
    """(Pfad, Farb-Index) des zuletzt gesetzten Hintergrundbilds."""
    try:
        with open(SARCH_STATE_FILE) as f:
            lines = f.read().splitlines()
    except OSError:
        return "", 0
    path = lines[0].strip() if lines else ""
    try:
        idx = int(lines[1]) if len(lines) > 1 else 0
    except ValueError:
        idx = 0
    return path, idx

def _save_current_wallpaper(path: str, idx: int):
    try:
        os.makedirs(os.path.dirname(SARCH_STATE_FILE), exist_ok=True)
        with open(SARCH_STATE_FILE, "w") as f:
            f.write(f"{path}\n{idx}\n")
    except OSError:
        pass

def matugen_source_colors(wp: str, n: int = 5) -> list:
    """Kandidaten für die Quellfarbe. matugen gibt sie nur auf einem TTY aus,
    daher wie im alten Skript über 'script' mit kurzem Timeout."""
    inner = f"timeout 1 matugen image {shlex.quote(wp)} --dry-run 2>&1; true"
    fd, tmp = tempfile.mkstemp(prefix="sarch-matugen-")
    os.close(fd)
    try:
        subprocess.run(["script", "-q", "-c", inner, tmp], stdin=subprocess.DEVNULL,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        with open(tmp, errors="replace") as f:
            out = f.read()
    except (OSError, subprocess.SubprocessError):
        out = ""
    finally:
        try: os.unlink(tmp)
        except OSError: pass
    return re.findall(r'#[0-9A-Fa-f]{6}', out)[:n]

def apply_wallpaper(wp: str, idx: int, cache_dir: str, color: str = "") -> tuple:
    """Wallpaper setzen (mit Transition) + matugen + Vorschaubilder für rofi + optional Razer-Farbe.
    Gibt (ok, Fehlertext) zurück."""
    # Bild sofort mit der eingestellten Transition setzen (läuft parallel zu matugen)
    setter = os.path.expanduser("~/.config/sArch/bin/sarch_wallpaper_set.sh")
    if os.access(setter, os.X_OK):
        _spawn([setter, wp])
    elif shutil.which("awww"):
        _spawn(["awww", "img", wp, "--transition-type", "grow"])
    try:
        r = subprocess.run(["matugen", "image", wp, "--source-color-index", str(idx)],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=180)
    except (OSError, subprocess.SubprocessError) as e:
        return False, str(e)
    if r.returncode != 0:
        return False, (r.stderr or r.stdout or "matugen failed").strip()[-300:]
    os.makedirs(cache_dir, exist_ok=True)
    for name, geo in (("curr", "500x500"), ("curr_wide", "1000x500")):
        try:
            subprocess.run(["magick", wp, "-thumbnail", f"{geo}^", "-gravity", "center", "-extent", geo,
                            "-quality", "70", os.path.join(cache_dir, name)],
                           stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=60)
        except (OSError, subprocess.SubprocessError):
            pass                                  # Vorschaubild ist optional
    if color and shutil.which("razer-cli"):
        _spawn(["razer-cli", "-e", "static", "-c", color.lstrip("#")])
    _save_current_wallpaper(wp, idx)
    # Benachrichtigung mit dem neuen Bild (Dunst-Regel "sarch_wallpaper" zeigt es groß oben an)
    _spawn(["dunstify", "-a", "Themes", "-u", "low", "-t", "4000", "-c", "Wallpaper changed",
            "-h", "string:x-dunst-stack-tag:sarch-wallpaper",
            "-i", os.path.join(cache_dir, "curr_wide"), os.path.basename(wp)])
    return True, ""

# ── Schriften ──

_RE_DUNST_FONT = re.compile(r'^(\s*font\s*=\s*")([^"]*)(")', re.M)
_RE_ROFI_FONT  = re.compile(r'^(\s*mainfont:\s*")([^"]*)(")', re.M)
_RE_KITTY_FAM  = re.compile(r'^(font_family[ \t]+)(.*)$', re.M)
_RE_KITTY_SIZE = re.compile(r'^(font_size[ \t]+)(.*)$', re.M)

def _read_match(path: str, rx: re.Pattern) -> str:
    try:
        with open(path) as f:
            m = rx.search(f.read())
        return m.group(2).strip() if m else ""
    except OSError:
        return ""

def _replace_in_file(path: str, rx: re.Pattern, value: str) -> bool:
    try:
        with open(path) as f:
            txt = f.read()
    except OSError:
        return False
    new, n = rx.subn(lambda m: m.group(1) + value + (m.group(3) if m.lastindex >= 3 else ""), txt, count=1)
    if not n:
        return False
    try:
        with open(path, "w") as f:
            f.write(new)
        return True
    except OSError:
        return False

def _split_font_spec(spec: str) -> tuple:
    """'Don Graffiti 15' -> ('Don Graffiti', 15.0)"""
    m = re.match(r'^(.*\S)\s+(\d+(?:\.\d+)?)$', spec or "")
    return (m.group(1), float(m.group(2))) if m else ((spec or "").strip(), None)

def read_ui_font(rofi_files: list, dunst_files: list) -> tuple:
    for p in rofi_files:
        spec = _read_match(p, _RE_ROFI_FONT)
        if spec: return _split_font_spec(spec)
    for p in dunst_files:
        spec = _read_match(p, _RE_DUNST_FONT)
        if spec: return _split_font_spec(spec)
    return "", None

def write_ui_font(dunst_files: list, rofi_files: list, family: str, size: float) -> list:
    """Schreibt 'Family Size' nach dunst + rofi. Gibt die fehlgeschlagenen Dateien zurück."""
    spec, failed, done = f"{family} {_fmt_size(size)}", [], 0
    for files, rx in ((dunst_files, _RE_DUNST_FONT), (rofi_files, _RE_ROFI_FONT)):
        for p in files:
            if not os.path.exists(p):
                continue                      # z.B. Matugen-Template nicht vorhanden
            if _replace_in_file(p, rx, spec): done += 1
            else: failed.append(p)
    if not done and not failed:
        failed = dunst_files + rofi_files
    return failed

def read_kitty_font(path: str) -> tuple:
    fam  = _read_match(path, _RE_KITTY_FAM)
    size = _read_match(path, _RE_KITTY_SIZE)
    try: size = float(size)
    except ValueError: size = None
    return fam, size
