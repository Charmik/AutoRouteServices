#!/bin/bash
# Every Cyprus way the model covers: sample, fetch Esri windows, predict.
# Fetch runs as N shard processes (the machine is ours for this); each retries failed roads in 3 passes and
# exits 1 if any still fail (fetch_errors.*.csv). Raw tiles go to $SURFACE_ML_DATA/esri/tiles, read from disk when there.
source "$(dirname "$0")/../env.sh"
cd $S
C=$E/check
CK=$E/results_r2/20261119_131313Z/sus-epoch=02-val_acc=0.93443.ckpt
N=7
[ -s $C/cy_all.csv ] || $P sample_roads.py $C/cy_hw.geojsonseq all $C/cy_all.csv > $C/cy_all.log 2>&1
fetch() {     # $1 = extra args; returns 1 if any shard failed
  local pids=() bad=0
  for i in $(seq 0 $((N-1))); do
    $P esri_fetch.py $C/cy_all.csv $C/cy_all --workers 32 --shard $i/$N $1 >> $C/cy_all_fetch.$i.log 2>&1 & pids+=($!)
  done
  for p in "${pids[@]}"; do wait $p || bad=1; done
  $P esri_fetch.py --merge $C/cy_all >> $C/cy_all_fetch.log 2>&1
  return $bad
}
if ! fetch; then
  echo "fetch had failures, rerun in 10 min" >> $C/cy_all.log; sleep 600
  fetch || echo "FETCH FAILURES REMAIN, see cy_all/fetch_errors.csv" >> $C/cy_all.log
fi
$P gis_eval.py $CK $C/cy_all $C/cy_all.csv $C/pred_cy_all.csv --patch-m 30 --tta >> $C/cy_all.log 2>&1
echo DONE >> $C/cy_all.log
# raw tiles for the roads fetched before the tile cache existed (cached roads are read from disk)
fetch --tiles-only && echo TILES DONE >> $C/cy_all.log || echo "TILES FAILURES, see cy_all_fetch.*.log" >> $C/cy_all.log
