#!/usr/bin/env python3
"""
Battery + power-profile state stream for the eww battery popup.

Polls `upower` every 5s and emits a single JSON line per tick, suitable
for an eww `deflisten`. The popup is short-lived, so the 5s cadence is
plenty fast (and saves power vs faster polling).

If `powerprofilesctl` isn't installed/running, `profile_available` is
false and the popup hides its profile section.
"""
import glob
import json
import re
import shutil
import subprocess
import sys
import time


def upower_info():
    try:
        paths = subprocess.check_output(["upower", "-e"], text=True)
        bat = next((p.strip() for p in paths.splitlines() if "BAT" in p), None)
        if not bat:
            return {}
        raw = subprocess.check_output(["upower", "-i", bat], text=True)
    except Exception:
        return {}
    out = {}
    for line in raw.splitlines():
        m = re.match(r"\s+([\w\- ]+?):\s+(.+)$", line)
        if m:
            out[m.group(1).strip()] = m.group(2).strip()
    return out


def format_duration(raw):
    """'2.3 hours' / '45.0 minutes' / '' → '2h 18m' / '45m' / ''."""
    if not raw:
        return ""
    m = re.match(r"([\d.]+)\s+(\w+)", raw)
    if not m:
        return raw
    v = float(m.group(1))
    unit = m.group(2)
    if unit.startswith("hour"):
        mins = v * 60
    elif unit.startswith("minute"):
        mins = v
    elif unit.startswith("day"):
        mins = v * 1440
    else:
        return raw
    h, mm = int(mins // 60), int(round(mins % 60))
    return f"{h}h {mm}m" if h else f"{mm}m"


def power_profile():
    if not shutil.which("powerprofilesctl"):
        return ""
    try:
        return subprocess.check_output(
            ["powerprofilesctl", "get"], text=True, stderr=subprocess.DEVNULL
        ).strip()
    except Exception:
        return ""


def sysfs_percent():
    """Read battery percentage straight from sysfs.

    Why not use upower's `percentage`? upower polls sysfs on its own
    schedule and caches; a `upower -i` call right after a step change
    can return stale data — which is exactly why the popup percent
    used to lag the bar (the bar's `battery-capacity` deflisten reads
    sysfs directly). Reading sysfs here keeps both in sync.
    """
    for path in glob.glob("/sys/class/power_supply/BAT*/capacity"):
        try:
            with open(path) as f:
                return int(f.read().strip())
        except (OSError, ValueError):
            continue
    return 0


def emit():
    info = upower_info()
    state = info.get("state", "unknown")
    percent = sysfs_percent()

    rate_raw = info.get("energy-rate", "0 W")
    try:
        rate = f"{float(rate_raw.split()[0]):.1f} W"
    except (ValueError, IndexError):
        rate = rate_raw
    cycles = info.get("charge-cycles", "—")
    try:
        health = round(float(info.get("capacity", "0").rstrip("%")), 1)
    except ValueError:
        health = None

    # Time + label depend on state. upower omits both fields when fully
    # charged or when it can't estimate (very low rate, just unplugged).
    if "time to empty" in info:
        time_str = format_duration(info["time to empty"])
        time_label = "until empty"
    elif "time to full" in info:
        time_str = format_duration(info["time to full"])
        time_label = "until full"
    elif state == "fully-charged":
        time_str, time_label = "", "Fully charged"
    else:
        time_str, time_label = "", state.replace("-", " ").capitalize()

    profile = power_profile()

    print(json.dumps({
        "state": state,
        "percent": percent,
        "rate": rate,
        "cycles": cycles,
        "health": health,
        "time": time_str,
        "time_label": time_label,
        "profile": profile,
        "profile_available": bool(profile),
    }), flush=True)


if __name__ == "__main__":
    while True:
        emit()
        time.sleep(5)
