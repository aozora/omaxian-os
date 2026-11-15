#!/bin/bash
# shot.sh <vm> <tag> -> /workspace/omaxian-os/build/round17/shots/<vm>-<tag>.png
cd /workspace/omaxian-os; mkdir -p build/round17/shots; o=build/round17/shots/$1-$2
timeout 20 sudo python3 tools/qmon.py build/round17/$1.mon screendump /tmp/$1-$2.ppm >/dev/null; sudo chmod 644 /tmp/$1-$2.ppm
timeout 20 python3 -c "from PIL import Image; Image.open('/tmp/$1-$2.ppm').save('$o.png')"; sudo rm -f /tmp/$1-$2.ppm
