#!/bin/bash
# shot.sh <vm> <tag> -> /workspace/build/round19/shots/<vm>-<tag>.png
cd /workspace; mkdir -p build/round19/shots; o=build/round19/shots/$1-$2
timeout 20 sudo python3 tools/qmon.py build/round19/$1.mon screendump /tmp/$1-$2.ppm >/dev/null; sudo chmod 644 /tmp/$1-$2.ppm
timeout 20 python3 -c "from PIL import Image; Image.open('/tmp/$1-$2.ppm').save('$o.png')"; sudo rm -f /tmp/$1-$2.ppm
