#!/bin/bash
# Common Esri test: regions -> fetch -> zero-shot + NAIP-tuned SUSformer -> Esri fine-tunes -> eval
source "$(dirname "$0")/../env.sh"
cd $S
NAIP_CKPT=$SUS/results_ft/20261117_223333Z/sus-epoch=06-val_acc=0.97138.ckpt
REG="fr_provence de_bavaria au_victoria jp_hokkaido"
while ! grep -q DONE $E/osm/extract.log; do sleep 60; done
while ! grep -q DONE $E/fetch_us.log; do sleep 60; done
for r in $REG; do
  mkdir -p $E/$r; [ -f $E/$r/test.csv ] || nice -n 10 $P prep_region.py $E/osm/$r.geojsonseq $r $E/$r > $E/$r/prep.log 2>&1
done
for r in $REG; do for s in test train; do
  nice -n 10 $P esri_fetch.py $E/$r/$s.csv $E/$r/$s --workers 12 >> $E/fetch_regions.log 2>&1
done; done
echo FETCHED >> $E/fetch_regions.log
mkdir -p $E/pred
for r in us $REG; do
  [ -f $E/pred/zs30_$r.csv ] || nice -n 10 $P gis_infer.py $E/$r/test $E/$r/test.csv $E/pred/zs30_$r.csv --patch-m 30 >> $E/pred/log 2>&1
  [ -f $E/pred/naipft_$r.csv ] || nice -n 10 $P gis_eval.py $NAIP_CKPT $E/$r/test $E/$r/test.csv $E/pred/naipft_$r.csv --patch-m 30 --tta >> $E/pred/log 2>&1
done
echo PRED1 >> $E/pred/log
nice -n 10 $P esri_merge.py $E $E/all us $REG >> $E/pred/log 2>&1
for v in naipinit release; do
  INIT=""; [ $v = naipinit ] && INIT="--init-ckpt $NAIP_CKPT"
  nice -n 10 $P gis_train.py $E/all/train $E/all/val $E/all $E/results_$v --patch-m 30 --patch-px 128 --epochs 6 $INIT > $E/train_$v.out 2>&1
  BEST=$(grep "Best checkpoint:" $E/train_$v.out | tail -1 | cut -d' ' -f3)
  for r in us $REG; do
    nice -n 10 $P gis_eval.py $BEST $E/$r/test $E/$r/test.csv $E/pred/esri_${v}_$r.csv --patch-m 30 --tta >> $E/pred/log 2>&1
  done
  echo "TRAINED $v" >> $E/pred/log
done
nice -n 10 $P esri_eval.py $E us $REG > $E/eval.out 2>&1
echo DONE >> $E/pred/log
