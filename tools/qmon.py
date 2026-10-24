#!/usr/bin/env python3
"""Tiny QEMU HMP monitor client.
  qmon.py <socket> screendump <file.png>
  qmon.py <socket> sendkey ctrl-alt-f2
  qmon.py <socket> type "some text\\n"     (types ASCII via sendkey)
  qmon.py <socket> mouse <x> <y> [click]   (absolute, usb-tablet; 0..32767)
  qmon.py <socket> hmp "info status"
"""
import socket, sys, time
KEYS = {' ': 'spc', '\n': 'ret', '-': 'minus', '=': 'equal', '.': 'dot', ',': 'comma',
        '/': 'slash', ';': 'semicolon', "'": 'apostrophe', '\t': 'tab', '_': 'shift-minus',
        ':': 'shift-semicolon', '!': 'shift-1', '@': 'shift-2', '"': 'shift-apostrophe',
        '|': 'shift-backslash', '\\': 'backslash', '>': 'shift-dot', '<': 'shift-comma',
        '*': 'shift-8', '&': 'shift-7', '$': 'shift-4', '(': 'shift-9', ')': 'shift-0',
        '~': 'shift-grave_accent', '#': 'shift-3', '+': 'shift-equal', '?': 'shift-slash'}
def cmd(sock, c):
    s = socket.socket(socket.AF_UNIX); s.connect(sock); s.settimeout(5)
    time.sleep(0.05)
    try: s.recv(65536)
    except Exception: pass
    s.sendall((c + '\n').encode()); time.sleep(0.3)
    out = b''
    try:
        while True:
            d = s.recv(65536)
            if not d: break
            out += d
            if len(d) < 65536: break
    except Exception: pass
    s.close(); return out.decode(errors='replace')
sock, op = sys.argv[1], sys.argv[2]
if op == 'screendump':
    print(cmd(sock, f'screendump {sys.argv[3]} -f png'))
elif op == 'sendkey':
    print(cmd(sock, f'sendkey {sys.argv[3]}'))
elif op == 'type':
    for ch in sys.argv[3].encode().decode('unicode_escape'):
        k = KEYS.get(ch) or (('shift-' + ch.lower()) if ch.isupper() else ch)
        cmd(sock, f'sendkey {k}'); time.sleep(0.05)
elif op == 'mouse':
    x, y = int(sys.argv[3]), int(sys.argv[4])
    # absolute pointer via usb-tablet: QEMU HMP mouse_move is relative; use input-send-event via qmp-less HMP
    print(cmd(sock, f'mouse_move {x} {y}'))
    if len(sys.argv) > 5: cmd(sock, 'mouse_button 1'); time.sleep(0.1); cmd(sock, 'mouse_button 0')
elif op == 'hmp':
    print(cmd(sock, sys.argv[3]))
