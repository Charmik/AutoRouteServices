#!/bin/bash
# SUSformer zero-shot on our held-out roads, then windows for the training roads (for fine-tuning)
source "$(dirname "$0")/../env.sh"
cd $S
for pass in 1 2; do   # second pass retries transient errors
    nice -n 10 $P gis_fetch.py $NAIP/dataset_bin/dataset_val.csv $NAIP/features_bin.csv $NAIP/data/fetch_log.csv $SUS/val >> $SUS/fetch_val.out 2>&1
done
for m in 15 20 30; do
    nice -n 10 $P gis_infer.py $SUS/val $NAIP/dataset_bin/dataset_val.csv $SUS/zeroshot_val_${m}m.csv --patch-m $m --threads 8 >> $SUS/infer_val.out 2>&1
done
for pass in 1 2; do
    nice -n 10 $P gis_fetch.py $NAIP/dataset_bin/dataset_train.csv $NAIP/features_bin.csv $NAIP/data/fetch_log.csv $SUS/train >> $SUS/fetch_train.out 2>&1
done
