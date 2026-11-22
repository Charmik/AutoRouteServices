#!/bin/bash
# Final scoring of the main paved/unpaved run, after the experiment queue
source "$(dirname "$0")/../env.sh"
cd $D
while kill -0 $(cat naip/run_clean.pid) 2>/dev/null; do sleep 120; done
E=naip/eval
nice -n 10 $P $S/eval_ckpt.py "naip/results_bin/20261115_171004Z/model-0-epoch=07-val_acc=0.95488.ckpt" naip/dataset_bin \
    --threads 6 --out $E/val_e07.csv > $E/val_e07.out 2>&1
nice -n 10 $P $S/eval_ckpt.py "naip/results_bin/20261115_171004Z/model-0-epoch=07-val_acc=0.95488.ckpt" naip/dataset_bin \
    --tta --threads 6 --out $E/val_e07_tta.csv > $E/val_e07_tta.out 2>&1
nice -n 10 $P $S/eval_ckpt.py "naip/results_bin/20261115_171004Z/model-0-epoch=05-val_acc=0.95361.ckpt" \
    "naip/results_bin/20261115_171004Z/model-0-epoch=06-val_acc=0.95472.ckpt" "naip/results_bin/20261115_171004Z/model-0-epoch=07-val_acc=0.95488.ckpt" naip/dataset_bin \
    --tta --threads 6 --out $E/val_ens_tta.csv > $E/val_ens_tta.out 2>&1
for v in val_e07_tta val_ens_tta; do
    $P $S/stack_eval.py $E/$v.csv $E/osm_tags.csv $E/way_meta_all.csv > $E/${v}_stack.out 2>&1
    $P $S/age_eval.py $E/$v.csv $E/way_meta_all.csv naip/data/fetch_log.csv > $E/${v}_age.out 2>&1
done
$P $S/error_sheet.py $E/val_ens_tta_stack.csv $E/errors_final.png --prob-col p_stack --n 36
