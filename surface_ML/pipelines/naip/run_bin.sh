#!/bin/bash
# Paved/unpaved pipeline: wait for chip fetch, then probmasks, dataset, training
set -e
source "$(dirname "$0")/../env.sh"
cd $D
while kill -0 $(cat naip/fetch_bin.pid) 2>/dev/null; do sleep 60; done
# Second fetch pass retries transient errors
nice -n 10 $P $S/fetch_chips.py naip/features_bin.csv naip/data >> naip/fetch_bin.out 2>&1
nice -n 10 $P $S/make_probmasks.py naip/features_bin.csv naip/data --workers 6 > naip/probmask_bin.out 2>&1
$P $S/make_dataset.py naip/features_bin.csv naip/data naip/dataset_bin --binary --keep-split naip/dataset > naip/dataset_bin.out 2>&1
nice -n 10 $P $S/train_cpu.py naip/dataset_bin naip/results_bin \
    --init "naip/results/20261114_075455Z/model-0-epoch=09-val_loss=0.82790.ckpt" \
    --monitor val_acc --plateau --max-epochs 15 --patience 4 \
    --batch-size 64 --workers 2 --threads 6 > naip/train_bin.out 2>&1 &
echo $! > naip/train_bin.pid
wait
