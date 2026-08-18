#!/usr/bin/env python3
"""Einladungscodes verwalten.

  python3 sync/codes.py liste          Zustand aller Codes
  python3 sync/codes.py neu 5          fünf neue Codes erzeugen
  python3 sync/codes.py weg ABCD-1234  einen unbenutzten Code zurücknehmen
"""
import json
import secrets
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

W = ["npx", "--yes", "wrangler@4", "kv"]
ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"   # ohne 0/O und 1/I
huebsch = lambda c: f"{c[:4]}-{c[4:]}" if len(c) == 8 else c


def run(args):
    return subprocess.run(W + args, capture_output=True, text=True).stdout


def keys():
    raw = run(["key", "list", "--binding", "DB", "--remote"])
    start = raw.find("[")
    if start < 0:
        print("Ablage nicht erreichbar. Erst  npx wrangler login  ausführen.")
        sys.exit(1)
    return [k["name"] for k in json.loads(raw[start:]) if k["name"].startswith("invite:")]


def value(name):
    raw = run(["key", "get", "--binding", "DB", "--remote", name])
    start = raw.find("{")
    try:
        return json.loads(raw[start:]) if start >= 0 else {}
    except json.JSONDecodeError:
        return {}


def liste():
    names = sorted(keys())
    if not names:
        print("  Keine Codes hinterlegt.")
        return
    with ThreadPoolExecutor(max_workers=8) as pool:
        werte = list(pool.map(value, names))
    frei = belegt = 0
    for name, d in zip(names, werte):
        code = huebsch(name.split(":", 1)[1])
        if d.get("usedBy"):
            belegt += 1
            print(f"  {code}   eingelöst von {d['usedBy']} am {d.get('usedAt', '')[:10]}")
        else:
            frei += 1
            notiz = f"   ({d['note']})" if d.get("note") else ""
            print(f"  {code}   frei{notiz}")
    print(f"\n  {frei} frei, {belegt} eingelöst")


def neu(anzahl):
    codes = ["".join(secrets.choice(ALPHABET) for _ in range(8)) for _ in range(anzahl)]

    def lege_an(c):
        run(["key", "put", "--binding", "DB", f"invite:{c}", '{"note":"neu"}', "--remote"])
        return c

    with ThreadPoolExecutor(max_workers=8) as pool:
        for c in pool.map(lege_an, codes):
            print(f"  {huebsch(c)}")


def weg(code):
    c = "".join(ch for ch in code.upper() if ch.isalnum())
    run(["key", "delete", "--binding", "DB", f"invite:{c}", "--remote"])
    print(f"  zurückgenommen: {huebsch(c)}")


if __name__ == "__main__":
    befehl = sys.argv[1] if len(sys.argv) > 1 else "liste"
    if befehl == "liste":
        liste()
    elif befehl == "neu":
        neu(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
    elif befehl == "weg":
        weg(sys.argv[2])
    else:
        print(__doc__)
