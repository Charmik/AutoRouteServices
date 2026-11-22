#!/bin/bash
source "$(dirname "$0")/../env.sh"
cd $S
for s in test train; do nice -n 10 $P esri_fetch.py $E/us/$s.csv $E/us/$s --workers 12; done
echo DONE
