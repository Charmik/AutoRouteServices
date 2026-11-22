#!/usr/bin/env python3
""" Training-set variants for the label-recency experiment. Val split is shared and
    untouched; only train rows are filtered:
      recent  - way last edited < 1 year before the OSM extract
      gap     - way last edited within 1 year of its NAIP image date
      random  - random rows (control)
    Every variant is cut to the same number of rows per class, so differences come
    from which labels are kept, not from size or class balance.

    Usage: make_subsets.py dataset_dir way_meta.csv fetch_log.csv out_root
"""
import pathlib
import shutil
import sys

import pandas as pd

ds, meta_csv, log_csv, out_root = map(pathlib.Path, sys.argv[1:5])
train = pd.read_csv(ds / 'dataset_train.csv')
meta = pd.read_csv(meta_csv, names=['osm_id', 'version', 'ts'])
log = pd.read_csv(log_csv)
log = log[log['status'] == 'ok'].drop_duplicates('osm_id', keep='last')[['osm_id', 'naip_date']]
t = train.merge(meta, on='osm_id', how='left').merge(log, on='osm_id', how='left')
ts = pd.to_datetime(t['ts'])
age = (pd.Timestamp('2026-09-23', tz='UTC') - ts).dt.days / 365.25
gap = (ts - pd.to_datetime(t['naip_date']).dt.tz_localize('UTC')).dt.days / 365.25

subsets = {'recent': train[(age < 1).values], 'gap': train[(gap.abs() <= 1).values],
           'random': train}
k = min(s['class_num'].value_counts().min() for s in subsets.values())
subsets = {name: pd.concat([g.sample(k, random_state=0) for _, g in sub.groupby('class_num')])
           for name, sub in subsets.items()}
for name, sub in subsets.items():
    d = out_root / f'dataset_bin_{name}'
    d.mkdir(parents=True, exist_ok=True)
    sub.to_csv(d / 'dataset_train.csv', index=False)
    for f in ('dataset_val.csv', 'dataset_full.csv', 'class_weights.csv'):
        shutil.copy(ds / f, d / f)
    print(f'{name:7s} {len(sub):6d} train rows  unpaved share {(sub["class_num"] == 1).mean():.2f}')
print(f'full    {len(train):6d}')
