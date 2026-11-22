#!/bin/bash
# Round 2: 20k training roads per region (test sets unchanged), continue from the best Esri model
source "$(dirname "$0")/../env.sh"
cd $S
INIT=$E/results_naipinit/20261119_025142Z/sus-epoch=04-val_acc=0.93077.ckpt
REG="fr_provence de_bavaria au_victoria jp_hokkaido"
for r in $REG; do
  [ -f $E/$r/train20k.csv ] || nice -n 10 $P prep_region.py $E/osm/$r.geojsonseq $r $E/$r --n-train 20000 --train-only train20k.csv > $E/$r/prep20k.log 2>&1
done
[ -f $E/us/train20k.csv ] || $P - <<'Q'
import pandas as pd
import os; W=os.environ['SURFACE_ML_DATA']+'/'
f=pd.read_csv(W+'naip/features_bin.csv',usecols=['osm_id','osm_surface','highway','wkt','lon','lat','length','binary','source']).drop_duplicates('osm_id')
d=pd.read_csv(W+'naip/dataset_bin/dataset_train.csv')[['osm_id','class_num']].merge(f,on='osm_id')
old=pd.read_csv(W+'esri/us/train.csv')
s=pd.concat([old,d[~d.osm_id.isin(old.osm_id)].sample(15000,random_state=1)])
s['region']='us'; s['split']='train'; s.to_csv(W+'esri/us/train20k.csv',index=False); print(len(s))
Q
for r in us $REG; do
  # reuse windows already fetched for the round-1 training roads
  if [ ! -d $E/$r/train20k ]; then mkdir -p $E/$r/train20k; cp $E/$r/train/windows.csv $E/$r/train/imagery_meta.csv $E/$r/train20k/; fi
  nice -n 10 $P esri_fetch.py $E/$r/train20k.csv $E/$r/train20k --workers 12 >> $E/fetch_round2.log 2>&1
done
echo FETCHED >> $E/fetch_round2.log
TRAIN=train20k nice -n 10 $P esri_merge.py $E $E/all20k us $REG > $E/merge20k.log 2>&1
nice -n 10 $P gis_train.py $E/all20k/train $E/all20k/val $E/all20k $E/results_r2 --patch-m 30 --patch-px 128 --epochs 4 --init-ckpt $INIT > $E/train_r2.out 2>&1
BEST=$(grep "Best checkpoint:" $E/train_r2.out | tail -1 | cut -d' ' -f3)
for r in us $REG; do
  nice -n 10 $P gis_eval.py $BEST $E/$r/test $E/$r/test.csv $E/pred/esri_r2_$r.csv --patch-m 30 --tta >> $E/pred/log_r2 2>&1
done
echo DONE >> $E/pred/log_r2
