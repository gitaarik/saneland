#!/usr/bin/env bash
#
# Build the categorized "Browse apps" data for the start-menu flyout.
#
# Scans the freedesktop application directories, parses each .desktop
# entry, drops the ones a launcher shouldn't show (NoDisplay/Hidden/
# non-Application/no-Exec), strips Exec field codes, and buckets every
# app into ONE freedesktop main category. Emits a single JSON object:
#
#   { "categories": ["Accessories","Development",...],   # non-empty, ordered
#     "apps": { "Development": [ {name, icon, path, cmd}, ... ], ... } }
#
#   name  display name (from Name=)
#   icon  themed icon NAME for eww `image :icon` (empty if we resolved a file)
#   path  absolute icon file for eww `image :path` (empty if a themed name)
#   cmd   ready to drop into  sh -c '<cmd>'  — single quotes are pre-escaped
#
# Consumed by eww.yuck (start-apps var) via popup-toggle.sh on menu open.
#
# Result is cached in $XDG_RUNTIME_DIR and only rebuilt when one of the
# application dirs has changed (mtime newer than the cache), so opening
# the menu is instant on the common no-change path.

set -uo pipefail

cache=${XDG_RUNTIME_DIR:-/tmp}/eww-start-apps.json

dirs=(
    /usr/share/applications
    /usr/local/share/applications
    "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
    /var/lib/flatpak/exports/share/applications
    "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/exports/share/applications"
)

# Fast path: reuse the cache unless an existing app dir is newer than it.
if [[ -f $cache ]]; then
    stale=0
    for d in "${dirs[@]}"; do
        [[ -d $d && $d -nt $cache ]] && { stale=1; break; }
    done
    if [[ $stale -eq 0 ]]; then
        cat "$cache"
        exit 0
    fi
fi

python3 - "${dirs[@]}" <<'PY' | tee "$cache"
import json, os, sys, glob

dirs = sys.argv[1:]

# Ordered freedesktop main categories -> the raw Categories tokens that
# land an app there. First match (in this order) wins, so an app tagged
# both Network and Utility lands in Internet, not Accessories.
CATEGORIES = [
    ("Settings",    {"Settings", "DesktopSettings", "HardwareSettings"}),
    ("Development", {"Development"}),
    ("Internet",    {"Network"}),
    ("Multimedia",  {"AudioVideo", "Audio", "Video"}),
    ("Graphics",    {"Graphics"}),
    ("Office",      {"Office"}),
    ("Games",       {"Game"}),
    ("Science",     {"Science", "Education"}),
    ("System",      {"System"}),
    ("Accessories", {"Utility"}),
]
FALLBACK = "Other"
ORDER = [name for name, _ in CATEGORIES] + [FALLBACK]

# Exec field codes to drop (deprecated ones included). %% -> literal %.
FIELD_CODES = {"%f", "%F", "%u", "%U", "%d", "%D", "%n", "%N",
               "%i", "%c", "%k", "%v", "%m"}


def strip_exec(exec_str):
    # Tokenize loosely on whitespace; good enough since we only remove
    # standalone field-code tokens and never re-quote the rest.
    out = []
    for tok in exec_str.split():
        if tok in FIELD_CODES:
            continue
        out.append(tok.replace("%%", "%"))
    return " ".join(out).strip()


def parse(path):
    entry = {}
    in_main = False
    try:
        with open(path, encoding="utf-8", errors="ignore") as fh:
            for line in fh:
                line = line.rstrip("\n")
                if line.startswith("[") and line.endswith("]"):
                    in_main = line == "[Desktop Entry]"
                    continue
                if not in_main or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                # First occurrence wins (localized keys like Name[de] are
                # ignored because of the exact-key check).
                if k in ("Type", "Name", "Exec", "Icon", "Categories",
                         "NoDisplay", "Hidden", "Terminal") and k not in entry:
                    entry[k] = v
    except OSError:
        return None
    return entry


seen = set()          # desktop-file basenames already taken (dir precedence)
apps = {c: [] for c in ORDER}

for d in dirs:
    for path in sorted(glob.glob(os.path.join(d, "*.desktop"))):
        base = os.path.basename(path)
        if base in seen:
            continue
        seen.add(base)

        e = parse(path)
        if not e:
            continue
        if e.get("Type", "Application") != "Application":
            continue
        if e.get("NoDisplay", "").lower() == "true":
            continue
        if e.get("Hidden", "").lower() == "true":
            continue
        name = e.get("Name", "").strip()
        cmd = strip_exec(e.get("Exec", ""))
        if not name or not cmd:
            continue
        # Terminal apps need a terminal; wrap so they actually appear.
        if e.get("Terminal", "").lower() == "true":
            cmd = "kitty " + cmd

        cats = {c for c in e.get("Categories", "").split(";") if c}
        target = FALLBACK
        for cname, match in CATEGORIES:
            if cats & match:
                target = cname
                break

        icon = e.get("Icon", "").strip()
        icon_name, icon_path = icon, ""
        if icon.startswith("/"):
            icon_name, icon_path = "", icon

        apps[target].append({
            "name": name,
            "icon": icon_name,
            "path": icon_path,
            # Pre-escape single quotes for  sh -c '<cmd>'  in the onclick.
            "cmd": cmd.replace("'", "'\\''"),
        })

for c in apps:
    apps[c].sort(key=lambda a: a["name"].lower())

categories = [c for c in ORDER if apps[c]]
# The flyout indexes apps[start-apps-cat] unconditionally (even while the
# revealer is collapsed and start-apps-cat is still ""), so guarantee that
# key resolves to an empty list rather than an eww "no such key" error.
apps[""] = []
print(json.dumps({"categories": categories, "apps": apps}))
PY
