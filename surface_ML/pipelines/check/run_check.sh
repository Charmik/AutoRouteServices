#!/bin/bash
source "$(dirname "$0")/../env.sh"
cd $S
C=$E/check
CK=$E/results_r2/20261119_131313Z/sus-epoch=02-val_acc=0.93443.ckpt
nice -n 10 $P esri_fetch.py $C/de_untagged.csv $C/de_untagged --workers 12 >> $C/fetch.log 2>&1
while ! grep -q DONE $C/extract.log; do sleep 60; done
nice -n 10 $P sample_roads.py $C/cy_hw.geojsonseq tagged $C/cy_test.csv >> $C/sample.log 2>&1
nice -n 10 $P sample_roads.py $C/cy_hw.geojsonseq untagged $C/cy_untagged.csv >> $C/sample.log 2>&1
nice -n 10 $P sample_roads.py $C/us_nosurf.geojsonseq untagged $C/us_untagged.csv >> $C/sample.log 2>&1
for s in cy_test cy_untagged us_untagged; do nice -n 10 $P esri_fetch.py $C/$s.csv $C/$s --workers 12 >> $C/fetch.log 2>&1; done
for s in de_untagged cy_test cy_untagged us_untagged; do
  nice -n 10 $P gis_eval.py $CK $C/$s $C/$s.csv $C/pred_$s.csv --patch-m 30 --tta >> $C/eval.log 2>&1
done
echo DONE >> $C/eval.log
