#!/bin/bash
# Predict every Cyprus way (fetch already done by run_cy_all.sh), untagged first so the page can go up early.
# No flip TTA: 4x faster on this CPU-only box, -0.2 pt on the Cyprus test (92.07 vs 92.27).
source "$(dirname "$0")/../env.sh"
cd $S
C=$E/check
CK=$E/results_r2/20261119_131313Z/sus-epoch=02-val_acc=0.93443.ckpt
for s in untagged tagged; do
  $P gis_eval.py $CK $C/cy_all $C/cy_all_$s.csv $C/pred_cy_all_$s.csv --patch-m 30 --threads 8 --workers 3 >> $C/cy_pred.log 2>&1
  $P -c "import pandas as pd, glob; pd.concat([pd.read_csv(f) for f in sorted(glob.glob('$C/pred_cy_all_*.csv'))]).to_csv('$C/pred_cy_all.csv', index=False)"
  rm -rf $C/site/cyprus/sheets.new; $P build_check.py $C/site/cyprus.new cy_all >> $C/cy_pred.log 2>&1 \
    && rm -rf $C/site/cyprus/sheets $C/site/cyprus/roads.json && mv $C/site/cyprus.new/sheets $C/site/cyprus.new/roads.json $C/site/cyprus/ && rm -rf $C/site/cyprus.new
  echo "PAGE $s $(date -Is)" >> $C/cy_pred.log
done
echo DONE >> $C/cy_pred.log
# raw tiles for the roads fetched before the tile cache existed (cached roads are read from disk)
for i in $(seq 0 6); do $P esri_fetch.py $C/cy_all.csv $C/cy_all --workers 32 --shard $i/7 --tiles-only >> $C/cy_tiles.$i.log 2>&1 & done; wait
echo TILES DONE >> $C/cy_pred.log
