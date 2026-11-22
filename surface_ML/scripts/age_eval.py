#!/usr/bin/env python3
""" Image-model accuracy vs. how old the OSM way's last edit is, and vs. the gap
    between that edit and the NAIP image date. Tells whether training only on
    recently edited ways is likely to help.

    Usage: age_eval.py val_probs.csv way_meta.csv fetch_log.csv
"""
import sys

import numpy as np
import pandas as pd

df = pd.read_csv(sys.argv[1])
meta = pd.read_csv(sys.argv[2], names=['osm_id', 'version', 'ts'])
log = pd.read_csv(sys.argv[3])
log = log[log['status'] == 'ok'].drop_duplicates('osm_id', keep='last')[['osm_id', 'naip_date']]
df = df.merge(meta, on='osm_id', how='left').merge(log, on='osm_id', how='left')
df['ok'] = df['y_true'] == df['y_pred']
snap = pd.Timestamp('2026-09-23', tz='UTC')
ts = pd.to_datetime(df['ts'])
df['age_y'] = (snap - ts).dt.days / 365.25
df['gap_y'] = (ts - pd.to_datetime(df['naip_date']).dt.tz_localize('UTC')).dt.days / 365.25


def table(col, bins, labels):
    g = df.groupby(pd.cut(df[col], bins, labels=labels), observed=True)['ok']
    print(pd.DataFrame({'n': g.size(), 'acc': g.mean().round(4)}).to_string())


print(f'overall acc {df["ok"].mean():.4f}  n={len(df)}\n')
print('by age of last way edit (years before 2026-09 extract):')
table('age_y', [0, 1 / 12, 0.5, 1, 2, 4, 8, 20], ['<1mo', '1-6mo', '6-12mo', '1-2y', '2-4y', '4-8y', '>8y'])
print('\nby last edit minus NAIP image date (years; negative = tag older than image):')
table('gap_y', [-20, -4, -2, -1, 0, 1, 2, 4, 20], ['<-4', '-4..-2', '-2..-1', '-1..0', '0..1', '1..2', '2..4', '>4'])
print('\nby way version (number of edits):')
table('version', [0, 1, 2, 4, 8, 1000], ['1', '2', '3-4', '5-8', '>8'])
