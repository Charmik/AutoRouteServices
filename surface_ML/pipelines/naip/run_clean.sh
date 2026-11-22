#!/bin/bash
# Label-cleaning experiment, after the recency experiments
source "$(dirname "$0")/../env.sh"
cd $D
while kill -0 $(cat naip/run_exp.pid) 2>/dev/null; do sleep 120; done
nice -n 10 $P $S/eval_ckpt.py "naip/results/20261114_075455Z/model-0-epoch=09-val_loss=0.82790.ckpt" \
    naip/dataset_bin_oos --threads 6 --out naip/eval/oos_8class.csv > naip/eval/oos_8class.out 2>&1
$P $S/make_clean_subset.py naip/dataset_bin naip/eval/oos_8class.csv \
    naip/dataset_bin_clean > naip/eval/clean_subset.out 2>&1
nice -n 10 $P $S/train_cpu.py naip/dataset_bin_clean naip/results_exp_clean \
    --init "naip/results/20261114_075455Z/model-0-epoch=09-val_loss=0.82790.ckpt" \
    --monitor val_acc --plateau --max-epochs 5 --patience 3 \
    --batch-size 64 --workers 2 --threads 6 > naip/train_exp_clean.out 2>&1
