#!/bin/bash
# Label-recency experiment: after the main paved/unpaved run, train the same model on
# equal-size recent / gap / random training subsets and score each on the shared val split
source "$(dirname "$0")/../env.sh"
cd $D
while kill -0 $(cat naip/train_bin.pid) 2>/dev/null; do sleep 120; done
for v in recent gap random; do
    nice -n 10 $P $S/train_cpu.py naip/dataset_bin_$v naip/results_exp_$v \
        --init "naip/results/20261114_075455Z/model-0-epoch=09-val_loss=0.82790.ckpt" \
        --monitor val_acc --plateau --max-epochs 5 --patience 3 \
        --batch-size 64 --workers 2 --threads 6 > naip/train_exp_$v.out 2>&1
done
