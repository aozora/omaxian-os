#!/usr/bin/env python3
# mon.py <vm> <cmd...> | mon.py <vm> --type "text" | --keys "ctrl-alt-t ret ..." | --shot name
# QEMU HMP monitor helper (build/qemu-<vm>.mon); --shot writes shots/<name>.png
import socket, sys, time, os
vm, args = sys.argv[1], sys.argv[2:]
def hmp(cmd):
    s = socket.socket(socket.AF_UNIX); s.connect(f"build/qemu-{vm}.mon"); s.settimeout(3)
    try:
        s.recv(4096)
    except Exception: pass
    s.sendall((cmd + "\n").encode()); time.sleep(0.15); out = b""
    try:
        while True:
            d = s.recv(65536)
            if not d: break
            out += d
            if len(d) < 65536: break
    except Exception: pass
    s.close(); return out.decode(errors="replace")
KEY = {" ": "spc", "\n": "ret", "-": "minus", "=": "equal", "/": "slash", ".": "dot", ",": "comma",
       ";": "semicolon", "'": "apostrophe", "\\": "backslash", "[": "bracket_left", "]": "bracket_right",
       "`": "grave_accent", "\t": "tab", "*": "shift-8", "|": "shift-backslash", "_": "shift-minus",
       ":": "shift-semicolon", '"': "shift-apostrophe", ">": "shift-dot", "<": "shift-comma", "~": "shift-grave_accent",
       "&": "shift-7", "$": "shift-4", "!": "shift-1", "(": "shift-9", ")": "shift-0", "+": "shift-equal",
       "@": "shift-2", "#": "shift-3", "%": "shift-5", "^": "shift-6", "?": "shift-slash", "{": "shift-bracket_left", "}": "shift-bracket_right"}
if args[0] == "--type":
    s = socket.socket(socket.AF_UNIX); s.connect(f"build/qemu-{vm}.mon"); s.settimeout(0.05)
    for ch in args[1]:
        k = KEY.get(ch) or (("shift-" + ch.lower()) if ch.isupper() else ch)
        s.sendall(("sendkey " + k + "\n").encode()); time.sleep(0.04)
        try:
            s.recv(65536)
        except Exception: pass
    s.close()
elif args[0] == "--keys":
    for k in args[1].split():
        hmp("sendkey " + k); time.sleep(0.25)
elif args[0] == "--shot":
    p = os.path.abspath(f"build/{args[1]}.ppm"); hmp("screendump " + p); time.sleep(1)
    from PIL import Image
    Image.open(p).save(f"shots/{args[1]}.png"); os.remove(p); print(f"shots/{args[1]}.png")
else:
    print(hmp(" ".join(args)))
