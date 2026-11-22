#!/bin/bash
# Flip-averaged scores from the 2nd and 3rd best fine-tuned SUSformer checkpoints, for a checkpoint ensemble
source "$(dirname "$0")/../env.sh"
cd $S
for e in 04 05; do
  nice -n 10 $P gis_eval.py $(ls $SUS/results_ft/20261117_223333Z/sus-epoch=${e}-*.ckpt) $SUS/val $NAIP/dataset_bin/dataset_val.csv $SUS/ft_val_e${e}.csv --patch-m 30 --tta --threads 8 >> $SUS/eval_ens.out 2>&1
done
