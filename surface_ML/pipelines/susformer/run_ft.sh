#!/bin/bash
# Fine-tune SUSformer on NAIP (patch size $1 m), score the held-out roads with flips, combine with ours
M=${1:-20}
source "$(dirname "$0")/../env.sh"
cd $S
nice -n 10 $P gis_train.py $SUS/train $SUS/val $NAIP/dataset_bin $SUS/results_ft --patch-m $M --patch-px 128 --epochs 8 >> $SUS/train_ft.out 2>&1
BEST=$(grep "Best checkpoint:" $SUS/train_ft.out | tail -1 | cut -d' ' -f3)
nice -n 10 $P gis_eval.py $BEST $SUS/val $NAIP/dataset_bin/dataset_val.csv $SUS/ft_val.csv --patch-m $M --tta >> $SUS/eval_ft.out 2>&1
nice -n 10 $P combine_eval.py $NAIP/eval/val_ens_tta.csv $SUS/ft_val.csv $NAIP/eval/osm_tags.csv $NAIP/eval/way_meta_all.csv $SUS/ft >> $SUS/combine_ft.out 2>&1
