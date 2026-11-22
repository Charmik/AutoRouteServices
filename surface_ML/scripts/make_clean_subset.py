#!/usr/bin/env python3
""" Label-cleaning experiment: drop training rows whose OSM label an out-of-sample model
    confidently contradicts, then sample the same per-class size as the other
    make_subsets.py variants.

    Usage: make_clean_subset.py dataset_dir oos_probs.csv out_dir [--per-class 3610] [--conf 0.9]
"""
import argparse
import pathlib
import shutil

import pandas as pd

ap = argparse.ArgumentParser()
ap.add_argument('dataset_dir')
ap.add_argument('oos_csv')
ap.add_argument('out_dir')
ap.add_argument('--per-class', type=int, default=3610)
ap.add_argument('--conf', type=float, default=0.9)
args = ap.parse_args()

ds, out = pathlib.Path(args.dataset_dir), pathlib.Path(args.out_dir)
train = pd.read_csv(ds / 'dataset_train.csv')
oos = pd.read_csv(args.oos_csv)
p_true = oos['p_unpaved'].where(oos['y_true'] == 1, 1 - oos['p_unpaved'])
flagged = set(oos.loc[p_true < 1 - args.conf, 'osm_id'])
print(f'{len(flagged)} of {len(oos)} scored rows flagged ({len(flagged) / len(oos):.1%})')
clean = train[~train['osm_id'].isin(flagged)]
sub = pd.concat([g.sample(args.per_class, random_state=0) for _, g in clean.groupby('class_num')])
out.mkdir(parents=True, exist_ok=True)
sub.to_csv(out / 'dataset_train.csv', index=False)
for f in ('dataset_val.csv', 'dataset_full.csv', 'class_weights.csv'):
    shutil.copy(ds / f, out / f)
print(f'clean subset: {len(sub)} rows')
