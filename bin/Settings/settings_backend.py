#!/usr/bin/env python3
"""
settings_backend.py – JSON-Backend für die Quickshell-Einstellungen (sarch-settings).

Die Quickshell-Oberfläche (~/.config/quickshell/sarch) ruft dieses Skript
per Process auf. Jeder Aufruf ist zustandslos: INI + Konfigdateien werden frisch
gelesen, das Ergebnis geht als genau ein JSON-Objekt nach stdout.

Aufruf:
  settings_backend.py <settings.ini> [--lang de] <befehl> [argumente …]

Befehle:
  model                         Kategorien, Gruppen, Einträge inkl. aktueller Werte
  apply   '<json>'              {"changes": [{"uid": …, "value": …} | {"uid": …, "fields": {…}}]}
  delete  '<json>'              {"uid": …}
  create  '<json>'              {"kind": "record|variable|command|rule", "section": …, …}
  wallpapers                    Liste der Hintergrundbilder + aktuelles Bild
  thumbs                        fehlende Vorschaubilder erzeugen (kann dauern)
  colors  <bild>                Kandidaten für die Akzentfarbe (matugen)
  scheme  <bild> <index>        komplettes Farbschema als Vorschau (matugen --dry-run)
  set-wallpaper <bild> <index> [farbe]
  fonts                         aktuelle Schriften + installierte Familien
  apply-fonts '<json>'          {"ui": {"family", "size"}, "term": {"family", "size"}}
  bar                           Bar-Konfiguration (bar.json)
  apply-bar   '<json>'          bar.json schreiben

Die eigentliche Lese-/Schreiblogik liegt in settings_core.py.
"""

import contextlib, copy, json, os, re, shutil, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import settings_core as core  # noqa: E402
from settings_core import (  # noqa: E402
    load_categories, load_i18n, _find_all_indexed_blocks,
    read_current_value, read_current_string, read_keybind_fields,
    write_value, write_keybind_fields, delete_entry,
    read_variables, write_variable, delete_variable, append_variable,
    read_animations, write_animation, append_animation, delete_line,
    read_autostarts, write_autostart, append_autostart,
    read_workspace_rules, write_workspace_rule, append_workspace_rule,
    read_layer_rules, write_layer_rule, append_layer_rule,
    append_new_entry, _build_hl_bind, _build_windowrule, _build_lua_func,
    list_wallpapers, read_current_wallpaper, matugen_source_colors, apply_wallpaper,
    read_ui_font, write_ui_font, read_kitty_font, _replace_in_file,
    _RE_KITTY_FAM, _RE_KITTY_SIZE, _x, _split_paths, _spawn, _notify, _fmt_size,
)

QS_THUMB_DIR = os.path.expanduser("~/.cache/sArch/qs_thumbs")
QS_THUMB_GEO = "560x340"

# Material-Symbols-Icons (Ligaturen) – überschreibbar per "icon = …" in der INI
CATEGORY_ICONS = {
    "allgemein": "tune", "general": "tune",
    "input": "mouse", "eingabe": "mouse",
    "monitore": "desktop_windows", "monitors": "desktop_windows",
    "keybindings": "keyboard", "tastenkürzel": "keyboard",
    "window rules": "select_window", "fensterregeln": "select_window",
    "variablen": "data_object", "variables": "data_object",
    "animationen": "animation", "animations": "animation",
    "autostart": "rocket_launch",
    "workspaces": "space_dashboard",
    "layer rules": "layers",
    "hintergrund": "wallpaper", "wallpaper": "wallpaper",
    "schriften": "font_download", "fonts": "font_download",
    "benachrichtigungen": "notifications", "notifications": "notifications",
    "leiste": "toolbar", "bar": "toolbar",
}
TYPE_ICONS = {"bar": "toolbar", "wallpaper": "wallpaper", "fonts": "font_download", "variable": "data_object",
              "autostart": "rocket_launch", "animation": "animation",
              "workspace_rule": "space_dashboard", "layer_rule": "layers"}

# Feld-Definitionen der alten Spezialtypen (type = animation / workspace_rule / layer_rule)
LEGACY_RULES = {
    "animation": {
        "index": "leaf", "reader": read_animations,
        "writer": lambda c, l, f: write_animation(c, l, f),
        "appender": lambda c, v: append_animation(c, v),
        "fields": [
            {"key": "leaf", "label": "Leaf (Name)", "type": "text"},
            {"key": "enabled", "label": "Aktiviert", "type": "dropdown", "options": ["true", "false"]},
            {"key": "speed", "label": "Geschwindigkeit", "type": "text"},
            {"key": "bezier", "label": "Bezier", "type": "text"},
            {"key": "spring", "label": "Spring", "type": "text"},
            {"key": "style", "label": "Style", "type": "text"},
        ]},
    "workspace_rule": {
        "index": "workspace", "reader": read_workspace_rules,
        "writer": lambda c, l, f: write_workspace_rule(c, l, {k: v for k, v in f.items() if v and k != "_line"}),
        "appender": lambda c, v: append_workspace_rule(c, {k: x for k, x in v.items() if x}),
        "fields": [
            {"key": "workspace", "label": "Workspace", "type": "text"},
            {"key": "default_name", "label": "Name", "type": "text"},
            {"key": "monitor", "label": "Monitor", "type": "text"},
            {"key": "layout", "label": "Layout", "type": "dropdown", "options": ["", "scrolling", "dwindle", "master"]},
            {"key": "default", "label": "Standard", "type": "dropdown", "options": ["", "true", "false"]},
        ]},
    "layer_rule": {
        "index": "name", "reader": read_layer_rules,
        "writer": lambda c, l, f: write_layer_rule(c, l, f),
        "appender": lambda c, v: append_layer_rule(c, v),
        "fields": [
            {"key": "name", "label": "Name", "type": "text"},
            {"key": "namespace", "label": "Namespace (Regex)", "type": "text"},
            {"key": "blur", "label": "Blur", "type": "dropdown", "options": ["", "true", "false"]},
        ]},
}

SPECIAL_TYPES = ("variable", "autostart", "wallpaper", "fonts", "bar") + tuple(LEGACY_RULES)


# ── Hilfen ────────────────────────────────────────────────────────────────────

def _num(v):
    """float -> int, wenn ganzzahlig (für hübsches JSON)."""
    return int(v) if float(v).is_integer() else float(v)


def _resolve_mainmod(config_file: str) -> str:
    """mainMod aus variables.lua neben der Konfigdatei auflösen (für Tastenkappen)."""
    path = os.path.join(os.path.dirname(config_file or ""), "variables.lua")
    for name, value, _ in read_variables(path):
        if name == "mainMod":
            return value.strip().strip('"\'')
    return "SUPER"


def _expand(settings: list) -> list:
    """index_field ohne index_value -> ein Eintrag pro gefundenem Block (wie die GTK-Maske)."""
    out = []
    for s in settings:
        if s["index_field"] and not s["index_value"] and s["config_file"]:
            try:
                with open(s["config_file"]) as f:
                    lines = f.readlines()
                for val, _, _ in _find_all_indexed_blocks(lines, s["index_field"]):
                    sc = copy.deepcopy(s)
                    sc["index_value"] = val
                    out.append(sc)
            except OSError:
                out.append(s)
        else:
            out.append(s)
    return out


def _field_defs(fields: list) -> list:
    return [{"key": f.get("key", ""), "label": f.get("label", f.get("key", "")),
             "type": f.get("type", "text"), "options": list(f.get("options", [])),
             "block": f.get("block", "")} for f in fields]


def _record_item(s: dict, uid: str, mainmod: str) -> dict:
    cur = read_keybind_fields(s["config_file"], s)
    fields = []
    for fd in _field_defs(s.get("fields", [])):
        if fd["block"]:
            val = cur.get(fd["key"], "")
        else:
            val = cur.get(fd["key"], fd["options"][0] if fd["options"] else "")
        fd["value"] = str(val)
        fields.append(fd)

    keys = []
    if "use_mainmod" in cur:                      # hl.bind()-Zeile
        if cur.get("use_mainmod") == "yes":
            keys.append(mainmod)
        if cur.get("modifier", "none") not in ("", "none"):
            keys.append(cur["modifier"])
        if cur.get("key"):
            keys.append(cur["key"])

    return {
        "kind": "record", "uid": uid, "section": s["section"],
        "title": cur.get("description") or s["index_value"] or s["label"],
        "keys": keys, "fields": fields, "deletable": True,
    }


# ── Modell ────────────────────────────────────────────────────────────────────

def collect(ini_path: str):
    """
    Baut das komplette UI-Modell und gleichzeitig eine uid -> Eintrag Tabelle,
    damit apply/delete exakt dieselben Einträge wiederfinden.
    """
    cats = load_categories(ini_path)
    model, lookup = [], {}

    for cat_name, settings in cats.items():
        icon = next((s["extra"].get("icon") for s in settings if s["extra"].get("icon")), "")
        if not icon:
            icon = CATEGORY_ICONS.get(cat_name.lower(), "")
        if not icon:
            icon = next((TYPE_ICONS[s["type"]] for s in settings if s["type"] in TYPE_ICONS), "settings")

        tmpl = next((s for s in settings if s.get("new_template")), None)
        groups, cur_group = [], None

        def settings_group(title):
            nonlocal cur_group
            if cur_group is None or cur_group["kind"] != "settings" or cur_group["title"] != title:
                cur_group = {"kind": "settings", "title": title, "description": "", "items": []}
                groups.append(cur_group)
            return cur_group

        def records_group(s):
            nonlocal cur_group
            if cur_group is None or cur_group["kind"] != "records":
                cur_group = {"kind": "records", "title": cat_name, "description": s["description"],
                             "items": [], "add": None}
                if tmpl:
                    cur_group["add"] = {"kind": "record", "section": tmpl["section"],
                                        "title": tmpl["label"], "fields": _field_defs(tmpl["fields"])}
                groups.append(cur_group)
            return cur_group

        mainmods = {}
        for s in _expand(settings):
            typ, sec, iv = s["type"], s["section"], s["index_value"]

            if typ in SPECIAL_TYPES:
                cur_group = None
                g = {"kind": typ, "title": s["label"] or cat_name, "description": s["description"],
                     "section": sec, "items": []}
                cfg = s["config_file"]
                if typ == "variable":
                    for name, value, line in read_variables(cfg):
                        uid = f"var|{sec}|{line}|{name}"
                        g["items"].append({"kind": "variable", "uid": uid, "name": name, "value": value})
                        lookup[uid] = ("variable", s, {"line": line, "name": name})
                    g["add"] = {"kind": "variable", "section": sec}
                elif typ == "autostart":
                    for e in read_autostarts(cfg):
                        uid = f"cmd|{sec}|{e['_line']}"
                        g["items"].append({"kind": "command", "uid": uid, "value": e["cmd"]})
                        lookup[uid] = ("command", s, {"line": e["_line"]})
                    g["add"] = {"kind": "command", "section": sec}
                elif typ in LEGACY_RULES:
                    spec = LEGACY_RULES[typ]
                    g["kind"] = "records"
                    for e in spec["reader"](cfg):
                        uid = f"rule|{sec}|{e['_line']}"
                        fields = []
                        for fd in _field_defs(spec["fields"]):
                            fd["value"] = str(e.get(fd["key"], "")).strip('"')
                            fields.append(fd)
                        g["items"].append({"kind": "record", "uid": uid, "section": sec,
                                           "title": str(e.get(spec["index"], f"Zeile {e['_line'] + 1}")).strip('"'),
                                           "keys": [], "fields": fields, "deletable": True})
                        lookup[uid] = ("rule", s, {"line": e["_line"]})
                    g["add"] = {"kind": "rule", "section": sec, "title": s["label"],
                                "fields": _field_defs(spec["fields"])}
                elif typ == "wallpaper":
                    g["dir"] = _x(s["extra"].get("wallpaper_dir", "~/Bilder/Wallpapers"))
                elif typ == "fonts":
                    pass
                elif typ == "bar":
                    g["file"] = _bar_file(s)
                groups.append(g)
                continue

            if typ == "multisetting":
                if not s.get("visible", True):
                    continue
                cfg = s["config_file"]
                if cfg not in mainmods:
                    mainmods[cfg] = _resolve_mainmod(cfg)
                uid = f"rec|{sec}|{iv}"
                records_group(s)["items"].append(_record_item(s, uid, mainmods[cfg]))
                lookup[uid] = ("record", s, {})
                continue

            # slider / dropdown
            uid = f"val|{sec}|{iv}"
            item = {"uid": uid, "label": s["label"], "description": s["description"],
                    "section": sec, "sub": iv}
            if typ == "dropdown":
                opts = s["options"]
                cur = read_current_string(s["config_file"], s, opts[0] if opts else "")
                item.update(kind="dropdown", options=opts, value=cur)
            else:
                cur = read_current_value(s["config_file"], s, s["min"])
                cur = max(s["min"], min(s["max"], cur))
                item.update(kind="slider", min=_num(s["min"]), max=_num(s["max"]),
                            step=_num(s["step"]), value=_num(cur))
            settings_group(iv or cat_name)["items"].append(item)
            lookup[uid] = (item["kind"], s, {})

        # Gruppen ohne sichtbaren Inhalt (z.B. nur Templates) bleiben trotzdem,
        # wenn man dort etwas anlegen kann.
        if tmpl and not any(g["kind"] == "records" for g in groups):
            cur_group = None
            records_group(tmpl)

        model.append({
            "name": cat_name, "icon": icon,
            "sections": [s["section"] for s in settings],
            "immediate": all(s["type"] == "wallpaper" for s in settings),
            "groups": groups,
        })
    return model, lookup


def _find_section(ini_path: str, typ: str) -> dict | None:
    for settings in load_categories(ini_path).values():
        for s in settings:
            if s["type"] == typ:
                return s
    return None


# ── Befehle ───────────────────────────────────────────────────────────────────

def cmd_model(ini, _args):
    model, _ = collect(ini)
    cur, idx = read_current_wallpaper()
    return {"ok": True, "strings": core._T, "categories": model,
            "wallpaper": {"current": cur, "index": idx}}


def cmd_apply(ini, args):
    payload = json.loads(args[0]) if args else {}
    _, lookup = collect(ini)
    errors, post = [], []

    for ch in payload.get("changes", []):
        uid = ch.get("uid", "")
        if uid not in lookup:
            errors.append(f"{uid}: nicht mehr vorhanden (Datei extern geändert?)")
            continue
        kind, s, meta = lookup[uid]
        cfg = s["config_file"]
        label = s.get("label") or s.get("config_key") or uid
        ok = False

        if kind in ("slider", "dropdown"):
            val = ch.get("value")
            if kind == "slider":
                val = float(val)
            ok = write_value(cfg, s, val)
            if ok:
                for mf in s.get("mirror_files", []):
                    if os.path.exists(mf) and not write_value(mf, s, val):
                        errors.append(f"{label} → {mf}")
                if s.get("on_apply") and s["on_apply"] not in post:
                    post.append(s["on_apply"])
        elif kind == "record":
            fvals = {k: str(v) for k, v in (ch.get("fields") or {}).items()}
            if s.get("lua_func"):
                fvals["__field_defs__"] = s.get("fields", [])
            ok = write_keybind_fields(cfg, s, fvals)
            label = s["index_value"] or label
        elif kind == "variable":
            ok = write_variable(cfg, meta["line"], meta["name"], str(ch.get("value", "")))
            label = meta["name"]
        elif kind == "command":
            ok = write_autostart(cfg, meta["line"], str(ch.get("value", "")))
        elif kind == "rule":
            fvals = {k: str(v) for k, v in (ch.get("fields") or {}).items()}
            fvals["_line"] = meta["line"]
            ok = LEGACY_RULES[s["type"]]["writer"](cfg, meta["line"], fvals)

        if not ok:
            errors.append(f"{label} → {cfg}")

    for c in post:
        _spawn(["bash", "-c", c])
    return {"ok": not errors, "errors": errors}


def cmd_delete(ini, args):
    payload = json.loads(args[0])
    _, lookup = collect(ini)
    uid = payload.get("uid", "")
    if uid not in lookup:
        return {"ok": False, "errors": [f"{uid}: nicht gefunden"]}
    kind, s, meta = lookup[uid]
    cfg = s["config_file"]
    if kind == "record":
        ok = delete_entry(cfg, s)
    elif kind == "variable":
        ok = delete_variable(cfg, meta["line"])
    elif kind in ("command", "rule"):
        ok = delete_line(cfg, meta["line"])
    else:
        ok = False
    return {"ok": ok, "errors": [] if ok else [core.t("error_delete_failed", file=cfg)]}


def _resolve_template(template: str, vals: dict) -> str:
    """{key}-Platzhalter ersetzen inkl. mainMod-Hilfsplatzhalter (wie die GTK-Maske)."""
    v = dict(vals)
    use_mm = v.get("use_mainmod", "yes") == "yes"
    mod = v.get("modifier", "none")
    v["use_mainmod_prefix"] = "mainMod .. " if use_mm else ""
    v["modifier_suffix"] = f'"{mod}" .. ' if mod != "none" else ""
    out = template
    for k, x in v.items():
        out = out.replace("{" + k + "}", str(x))
    return out.replace("\\n", "\n")


def cmd_create(ini, args):
    p = json.loads(args[0])
    kind, sec = p.get("kind"), p.get("section")
    s = next((x for xs in load_categories(ini).values() for x in xs if x["section"] == sec), None)
    if not s:
        return {"ok": False, "errors": [f"Sektion {sec} nicht gefunden"]}

    if kind == "variable":
        name, value = p.get("name", "").strip(), p.get("value", "").strip()
        if not name or not value:
            return {"ok": False, "errors": ["Name und Wert angeben"]}
        ok = append_variable(s["config_file"], name, value)
    elif kind == "command":
        val = p.get("value", "").strip()
        if not val:
            return {"ok": False, "errors": ["Befehl angeben"]}
        ok = append_autostart(s["config_file"], val)
    elif kind == "rule":
        ok = LEGACY_RULES[s["type"]]["appender"](s["config_file"], dict(p.get("values", {})))
    elif kind == "record":
        vals = {k: str(v) for k, v in (p.get("values") or {}).items()}
        template = s["new_template"]
        if template == "__lua_func__":
            # Fix ggü. GTK-Maske: lua_func + Felddefinitionen mitgeben (sonst "hl.unknown({ })")
            vals["__lua_func__"] = s.get("lua_func") or "hl.unknown"
            vals["__field_defs__"] = s.get("fields", [])
            ok = append_new_entry(s["append_file"], template, vals=vals)
        elif template in ("__keybind__", "__windowrule__"):
            ok = append_new_entry(s["append_file"], template, vals=vals)
        else:
            ok = append_new_entry(s["append_file"], _resolve_template(template, vals), vals=None)
    else:
        return {"ok": False, "errors": [f"unbekannter Typ {kind}"]}
    return {"ok": bool(ok), "errors": [] if ok else [f"Konnte nicht schreiben: {s.get('append_file') or s['config_file']}"]}


# ── Hintergrundbild ──

def _magick() -> list:
    return ["magick"] if shutil.which("magick") else ["convert"]


def _wp_section(ini):
    s = _find_section(ini, "wallpaper") or {"extra": {}}
    ex = s.get("extra", {})
    return _x(ex.get("wallpaper_dir", "~/Bilder/Wallpapers")), _x(ex.get("cache_dir", "~/.cache/Wallpaper_thumbs"))


def _qs_thumb(wp: str) -> str:
    return os.path.join(QS_THUMB_DIR, os.path.splitext(os.path.basename(wp))[0] + ".jpg")


def cmd_wallpapers(ini, _args):
    wp_dir, _ = _wp_section(ini)
    cur, idx = read_current_wallpaper()
    items = []
    ccache = core._load_color_cache()
    for wp in list_wallpapers(wp_dir):
        th = _qs_thumb(wp)
        fresh = os.path.exists(th) and os.path.getmtime(th) >= os.path.getmtime(wp)
        items.append({"path": wp, "name": os.path.splitext(os.path.basename(wp))[0],
                      "thumb": th if fresh else "",
                      "colors": core.cached_source_colors(wp, ccache)})   # None = noch nicht berechnet
    return {"ok": True, "dir": wp_dir, "current": cur, "index": idx, "items": items,
            "missing": sum(1 for i in items if not i["thumb"]),
            "missingColors": sum(1 for i in items if i["colors"] is None)}


def cmd_thumbs(ini, _args):
    wp_dir, cache = _wp_section(ini)
    os.makedirs(QS_THUMB_DIR, exist_ok=True)
    made = 0
    for wp in list_wallpapers(wp_dir):
        th = _qs_thumb(wp)
        if os.path.exists(th) and os.path.getmtime(th) >= os.path.getmtime(wp):
            continue
        try:
            r = subprocess.run(_magick() + [wp, "-thumbnail", f"{QS_THUMB_GEO}^", "-gravity", "center",
                                            "-extent", QS_THUMB_GEO, "-quality", "82", th],
                               stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=60)
            made += r.returncode == 0
        except (OSError, subprocess.SubprocessError):
            pass
    # die kleinen 100px-Thumbs für rofi & Co. weiterhin pflegen
    core.ensure_thumbnails(wp_dir, cache)
    return {"ok": True, "made": made}


def cmd_colors(_ini, args):
    return {"ok": True, "path": args[0], "colors": core.wallpaper_colors(args[0])}


def cmd_colors_all(ini, _args):
    """Farben für alle Wallpaper (fehlende werden parallel berechnet und gecacht)."""
    wp_dir, _ = _wp_section(ini)
    return {"ok": True, "colors": core.warm_wallpaper_colors(list_wallpapers(wp_dir))}


def _extract_scheme(data: dict, mode: str = "dark") -> dict:
    """Toleranter Parser für die verschiedenen matugen-JSON-Formate (v2 / v3)."""
    cols = data.get("colors", data)
    out = {}
    if isinstance(cols.get(mode), dict):                       # v2: colors.dark.primary
        cols = cols[mode]
        for k, v in cols.items():
            if isinstance(v, str):
                out[k] = v
        return out
    for k, v in cols.items():                                   # v3: colors.primary.dark
        if isinstance(v, str):
            out[k] = v
        elif isinstance(v, dict):
            x = v.get(mode) or v.get("default") or v.get("dark")
            if isinstance(x, dict):
                x = x.get("color") or x.get("hex")
            if isinstance(x, str):
                out[k] = x
    return out


def cmd_scheme(_ini, args):
    wp, idx = args[0], args[1] if len(args) > 1 else "0"
    try:
        r = subprocess.run(["matugen", "image", wp, "--source-color-index", str(idx),
                            "--dry-run", "--json", "hex"],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=30)
        txt = r.stdout
        data = json.loads(txt[txt.index("{"):])
        scheme = {k: v for k, v in _extract_scheme(data).items() if re.match(r"^#[0-9a-fA-F]{6}$", v)}
        return {"ok": bool(scheme), "path": wp, "index": int(idx), "scheme": scheme}
    except Exception as e:  # matugen fehlt / anderes Format -> Vorschau nur mit Akzentfarbe
        return {"ok": False, "path": wp, "index": int(idx), "scheme": {}, "error": str(e)[:200]}


def cmd_set_wallpaper(ini, args):
    wp, idx = args[0], int(args[1]) if len(args) > 1 else 0
    color = args[2] if len(args) > 2 else ""
    set_image = not (len(args) > 3 and args[3] == "noset")    # "noset": Bild wurde schon gesetzt
    _, cache = _wp_section(ini)
    ok, err = apply_wallpaper(wp, idx, cache, color, set_image)
    return {"ok": ok, "error": err, "path": wp, "index": idx}


# ── Bar ──

DEFAULT_BAR_FILE = "~/.config/quickshell/sarch/bar.json"


def _bar_file(s) -> str:
    return _x((s or {}).get("extra", {}).get("bar_file", DEFAULT_BAR_FILE))


def cmd_bar(ini, _args):
    path = _bar_file(_find_section(ini, "bar"))
    try:
        with open(path) as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    return {"ok": True, "file": path, "config": data}


def cmd_apply_bar(ini, args):
    cfg = json.loads(args[0])
    if not isinstance(cfg, dict):
        return {"ok": False, "errors": ["ungültige Bar-Konfiguration"]}
    path = _bar_file(_find_section(ini, "bar"))
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(cfg, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp, path)        # atomar, damit die Bar nie eine halbe Datei liest
    except OSError as e:
        return {"ok": False, "errors": [f"{path}: {e}"]}
    return {"ok": True, "file": path}


# ── Schriften ──

def _font_files(ini):
    s = _find_section(ini, "fonts") or {"extra": {}}
    ex = s.get("extra", {})
    return (_split_paths(ex.get("dunst_files", "~/.config/dunst/dunstrc")),
            _split_paths(ex.get("rofi_files", "~/.config/rofi/colors.rasi")),
            _x(ex.get("kitty_file", "~/.config/kitty/hyde.conf")))


def _fc_families(pattern: str) -> list:
    try:
        out = subprocess.run(["fc-list", pattern, "family"], capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    fams = {line.split(",")[0].strip() for line in out.splitlines() if line.strip()}
    return sorted(fams, key=str.lower)


def cmd_fonts(ini, _args):
    dunst, rofi, kitty = _font_files(ini)
    ui_fam, ui_size = read_ui_font(rofi, dunst)
    k_fam, k_size = read_kitty_font(kitty)
    all_f = _fc_families(":")
    mono = set(_fc_families(":spacing=mono")) | set(_fc_families(":spacing=dual"))
    mono |= {f for f in all_f if re.search(r"(?i)(mono|code|nerd|iosevka|courier)", f)}
    return {"ok": True,
            "ui": {"family": ui_fam, "size": ui_size or 12.0},
            "term": {"family": k_fam, "size": k_size or 10.0},
            "families": all_f, "mono": sorted(mono, key=str.lower)}


def cmd_apply_fonts(ini, args):
    p = json.loads(args[0])
    dunst, rofi, kitty = _font_files(ini)
    errors = []
    ui = p.get("ui")
    if ui and ui.get("family"):
        failed = write_ui_font(dunst, rofi, ui["family"], float(ui.get("size", 12)))
        if failed:
            errors += failed
        else:
            _spawn(["dunstctl", "reload"])
            _notify("Font changed", f"{ui['family']} {_fmt_size(float(ui.get('size', 12)))}")
    term = p.get("term")
    if term and term.get("family"):
        size = _fmt_size(float(term.get("size", 10)))
        w1 = _replace_in_file(kitty, _RE_KITTY_FAM, term["family"])
        w2 = _replace_in_file(kitty, _RE_KITTY_SIZE, size)
        if w1 and w2:
            _spawn(["pkill", "-USR1", "-x", "kitty"])
            _notify("Terminal font changed", f"{term['family']} {size}")
        else:
            errors.append(kitty)
    return {"ok": not errors, "errors": errors}


COMMANDS = {
    "model": cmd_model, "apply": cmd_apply, "delete": cmd_delete, "create": cmd_create,
    "wallpapers": cmd_wallpapers, "thumbs": cmd_thumbs, "colors": cmd_colors, "colors-all": cmd_colors_all,
    "scheme": cmd_scheme, "set-wallpaper": cmd_set_wallpaper,
    "fonts": cmd_fonts, "apply-fonts": cmd_apply_fonts,
    "bar": cmd_bar, "apply-bar": cmd_apply_bar,
}


def main(argv: list) -> int:
    lang = ""
    if "--lang" in argv:
        i = argv.index("--lang")
        lang = argv[i + 1] if i + 1 < len(argv) else ""
        del argv[i:i + 2]
    if len(argv) < 2 or argv[1] not in COMMANDS:
        print(json.dumps({"ok": False, "error": f"usage: {os.path.basename(__file__)} <ini> [--lang xx] "
                                                 f"<{'|'.join(COMMANDS)}> [args]"}))
        return 2
    ini, cmd, args = os.path.expanduser(argv[0]), argv[1], argv[2:]
    core._T = load_i18n(lang)

    real_stdout = sys.stdout
    try:
        # Warnungen der Core-Funktionen (print) nicht ins JSON mischen
        with contextlib.redirect_stdout(sys.stderr):
            if not os.path.exists(ini):
                raise FileNotFoundError(f"INI nicht gefunden: {ini}")
            result = COMMANDS[cmd](ini, args)
    except Exception as e:
        result = {"ok": False, "error": f"{type(e).__name__}: {e}", "errors": [str(e)]}
    result["cmd"] = cmd
    real_stdout.write(json.dumps(result, ensure_ascii=False) + "\n")
    real_stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
