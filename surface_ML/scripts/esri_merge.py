#!/usr/bin/env python3
""" Pool the Esri training roads of several regions into one gis_train.py dataset.
    A hashed tenth of each region's training cells becomes the validation set used for
    checkpoint choice, so the regions' test sets stay untouched.

    Usage: esri_merge.py esri_dir out_dir region [region ...]
    TRAIN env var: training list / windows name inside each region (default 'train')
"""
import os
import pathlib
import sys
import zlib

import pandas as pd

from prep_region import CELL_DEG

esri, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
roads, wins = [], []
for r in sys.argv[3:]:
    name = os.environ.get('TRAIN', 'train')
    d = pd.read_csv(esri / r / f'{name}.csv', low_memory=False)
    d['region'] = r
    roads.append(d[['osm_id', 'class_num', 'lon', 'lat', 'region']])
    wins.append(pd.read_csv(esri / r / name / 'windows.csv'))
roads, wins = pd.concat(roads), pd.concat(wins)
roads = roads[roads['osm_id'].isin(set(wins['osm_id']))]
cell = (roads['lon'] // CELL_DEG).astype(int).astype(str) + '_' + (roads['lat'] // CELL_DEG).astype(int).astype(str)
roads['split'] = ['val' if zlib.crc32(('v' + c).encode()) % 10 == 0 else 'train' for c in cell]
for s in ('train', 'val'):
    d = roads[roads['split'] == s]
    (out / s).mkdir(parents=True, exist_ok=True)
    d.to_csv(out / f'dataset_{s}.csv', index=False)
    wins[wins['osm_id'].isin(set(d['osm_id']))].to_csv(out / s / 'windows.csv', index=False)
    print(s, len(d), d.groupby('region')['class_num'].agg(['size', 'mean']).round(3).to_dict('index'))
