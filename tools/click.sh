#!/bin/sh
# click.sh <mon> <x> <y> : PS/2 relative pointer (mouse_set 2), home to top-left then step 10px
M=$1; X=$2; Y=$3; Q="python3 $(dirname "$0")/qmon.py $M hmp"
{ $Q "mouse_set 2"; for i in $(seq 20); do $Q "mouse_move -100 -100"; done
  while [ $X -gt 0 ]; do s=$((X>10?10:X)); $Q "mouse_move $s 0"; X=$((X-s)); done
  while [ $Y -gt 0 ]; do s=$((Y>10?10:Y)); $Q "mouse_move 0 $s"; Y=$((Y-s)); done
  $Q "mouse_button 1"; $Q "mouse_button 0"; } >/dev/null
