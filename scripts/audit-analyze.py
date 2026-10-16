#!/usr/bin/env python3
"""Reads out/audit.log (make log > out/audit.log) and prints, per audit report, the leftover paint and
the visible ids / classes your tweak does not mention.   usage: audit-analyze.py out/audit.log [tweak/Sources]"""
import re, sys, os, subprocess
log = open(sys.argv[1], errors="ignore").read()
src = sys.argv[2] if len(sys.argv) > 2 else "tweak/Sources"
code = subprocess.run(["grep", "-rhI", "", src], capture_output=True, text=True).stdout
# one report = parts "audit i/n" joined; strip syslog prefixes
text = "\n".join(re.sub(r"^.*?\[spotifyglass\] ", "", l) for l in log.splitlines())
reports = re.split(r"(?m)^audit 1/\d+\s*$", text)[1:]
for n, rep in enumerate(reports, 1):
    rep = re.sub(r"(?m)^audit \d+/\d+\s*$", "", rep)
    print(f"===== report {n} =====")
    m = re.search(r"windows:\n(.*?)leftover paint", rep, re.S)
    if m: print("windows:\n" + m.group(1).rstrip())
    m = re.search(r"leftover paint.*?\n(.*?)(?=visible ids)", rep, re.S)
    if m: print("leftover paint:\n" + m.group(0).rstrip())
    m = re.search(r"visible ids \(\d+\):\n(.*?)(?=visible classes)", rep, re.S)
    ids = m.group(1).split() if m else []
    print("\nids on screen NOT mentioned in the tweak:")
    for i in ids:
        if i not in code: print("  ", i)
    m = re.search(r"visible classes[^\n]*\n(.*)", rep, re.S)
    classes = re.findall(r"(\S+)x\d+", m.group(1)) if m else []
    print("\nSpotify classes on screen NOT mentioned in the tweak:")
    for c in classes:
        if c.rstrip("…") not in code: print("  ", c)
