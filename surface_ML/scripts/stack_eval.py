#!/usr/bin/env python3
""" Does OSM context (highway type, tracktype, TIGER class, ...) on top of the image
    model's paved/unpaved probability raise accuracy? Gradient-boosted stacker,
    scored with spatial cross-validation (folds by 1-degree cell) on the val split.
    Also prints accuracy vs. coverage when the least confident roads are left out.

    Usage: stack_eval.py val_probs.csv osm_tags.csv [way_meta.csv]
"""
import sys

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.model_selection import GroupKFold

probs, tags = pd.read_csv(sys.argv[1]), pd.read_csv(sys.argv[2])
df = probs.merge(tags, on='osm_id', how='left')
if len(sys.argv) > 3:
    meta = pd.read_csv(sys.argv[3], names=['osm_id', 'version', 'ts'])
    df = df.merge(meta, on='osm_id', how='left')
    df['age_y'] = (pd.Timestamp('2026-09-23', tz='UTC') - pd.to_datetime(df['ts'])).dt.days / 365.25
y = df['y_true'].values
p_img = df['p_unpaved'].clip(1e-6, 1 - 1e-6)
group = (np.floor(df['lon']) * 1000 + np.floor(df['lat'])).values


def num(s):
    return pd.to_numeric(s.astype(str).str.extract(r'([\d.]+)')[0], errors='coerce')


X = pd.DataFrame({'img_logit': np.log(p_img / (1 - p_img))})
basic = ['highway', 'tiger:cfcc', 'tiger:reviewed', 'oneway', 'bridge', 'access', 'service']
extra = ['tracktype', 'smoothness', 'lit', 'sidewalk', '4wd_only', 'motor_vehicle']
for c in basic + extra:
    X[c] = df[c].fillna('NA').astype('category')
X['has_ref'] = df['ref'].notna().astype(int)
X['has_name'] = df['name'].notna().astype(int)
X['lanes'] = num(df['lanes'])
X['maxspeed'] = num(df['maxspeed'])
X['n_tags'] = df['n_tags']
X['lat'], X['lon'] = df['lat'], df['lon']
if 'age_y' in df:
    X['version'], X['age_y'] = df['version'], df['age_y']

sets = {
    'image only': ['img_logit'],
    'tags only (basic)': basic + ['has_ref', 'has_name', 'lanes', 'maxspeed', 'n_tags'],
    'image + basic tags': ['img_logit'] + basic + ['has_ref', 'has_name', 'lanes', 'maxspeed'],
    'image + basic tags + location': ['img_logit'] + basic + ['has_ref', 'has_name', 'lanes',
                                                               'maxspeed', 'lat', 'lon'],
    'image + all tags + location': list(X.columns),
}
results = {}
for name, cols in sets.items():
    p = np.zeros(len(df))
    for tr, te in GroupKFold(5).split(X, y, group):
        m = HistGradientBoostingClassifier(max_iter=300, learning_rate=0.05,
                                           categorical_features='from_dtype', random_state=0)
        m.fit(X.iloc[tr][cols], y[tr])
        p[te] = m.predict_proba(X.iloc[te][cols])[:, 1]
    results[name] = p
    nat = (df['source'] == 'natural').values
    acc = ((p > 0.5) == y)
    print(f'{name:32s} acc {acc.mean():.4f}   natural-mix {acc[nat].mean():.4f}')

print(f"\nimage model alone, argmax:        acc {(df['y_pred'] == y).mean():.4f}")
for name in ('image only', 'image + all tags + location'):
    p = results[name]
    conf = np.abs(p - 0.5)
    order = np.argsort(-conf)
    ok = ((p > 0.5) == y)[order]
    print(f'\naccuracy vs coverage ({name}):')
    for cov in (1.0, 0.95, 0.9, 0.8, 0.7, 0.5):
        k = int(len(ok) * cov)
        print(f'  most confident {cov:4.0%}: {ok[:k].mean():.4f}')

df['p_stack'] = results['image + all tags + location']
df.to_csv(sys.argv[1].replace('.csv', '_stack.csv'), index=False)
