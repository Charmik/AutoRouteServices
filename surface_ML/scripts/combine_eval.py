#!/usr/bin/env python3
""" Compare and combine paved/unpaved models on the same held-out roads.

    For each model alone, simple rules over two models (both-say-paved, either-says-
    paved, probability average), and gradient-boosted stackers with and without OSM
    tags (spatial 5-fold CV by 1-degree cell). Also agreement statistics and accuracy
    vs. coverage.

    Usage: combine_eval.py ours.csv other.csv osm_tags.csv way_meta.csv out_prefix
             ours.csv:  eval_ckpt.py --out (osm_id, y_true, p_unpaved, lon, lat, source, ...)
             other.csv: gis_infer.py / gis_eval.py output (osm_id, p_unpaved)
"""
import sys

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.model_selection import GroupKFold

ours_csv, other_csv, tags_csv, meta_csv, out_prefix = sys.argv[1:6]
ours = pd.read_csv(ours_csv, low_memory=False)
other = pd.read_csv(other_csv)[['osm_id', 'p_unpaved']].rename(columns={'p_unpaved': 'p_other'})
df = ours.merge(other, on='osm_id', how='inner')
tags = pd.read_csv(tags_csv, low_memory=False)
meta = pd.read_csv(meta_csv, names=['osm_id', 'version', 'ts'])
df = df.merge(tags, on='osm_id', how='left').merge(meta, on='osm_id', how='left')
y = df['y_true'].values
nat = (df['source'] == 'natural').values
print(f'{len(df)} roads scored by both models (of {len(ours)} ours, {len(other)} other)\n')


def logit(p):
    p = np.clip(p, 1e-6, 1 - 1e-6)
    return np.log(p / (1 - p))


def report(name, p):
    ok = (p > 0.5) == y
    print(f'{name:44s} acc {ok.mean():.4f}   real-US-mix {ok[nat].mean():.4f}')
    return ok.mean()


pa, pb = df['p_unpaved'].values, df['p_other'].values
results = {}
results['ours'] = report('our model (MaskCNN, 3 versions x 4 flips)', pa)
results['other'] = report('SUSformer', pb)
# The user's rule: paved only when both models say paved
results['and'] = report('rule: paved only if both say paved', np.maximum(pa, pb))
results['or'] = report('rule: paved if either says paved', np.minimum(pa, pb))
results['avg'] = report('average of the two probabilities', (pa + pb) / 2)

agree = (pa > 0.5) == (pb > 0.5)
print(f'\nmodels agree on {agree.mean():.1%} of roads; accuracy there {((pa > 0.5) == y)[agree].mean():.4f}')
print(f'they disagree on {(~agree).sum()} roads: ours right {((pa > 0.5) == y)[~agree].mean():.1%}, '
      f'SUSformer right {((pb > 0.5) == y)[~agree].mean():.1%}\n')


def num(s):
    return pd.to_numeric(s.astype(str).str.extract(r'([\d.]+)')[0], errors='coerce')


X = pd.DataFrame({'ours': logit(pa), 'other': logit(pb)})
for c in ['highway', 'tiger:cfcc', 'tiger:reviewed', 'oneway', 'bridge', 'access', 'service',
          'tracktype', 'smoothness', 'lit', 'sidewalk', '4wd_only', 'motor_vehicle']:
    X[c] = df[c].fillna('NA').astype('category')
X['has_ref'] = df['ref'].notna().astype(int)
X['has_name'] = df['name'].notna().astype(int)
X['lanes'], X['maxspeed'] = num(df['lanes']), num(df['maxspeed'])
X['n_tags'], X['version'] = df['n_tags'], df['version']
X['age_y'] = (pd.Timestamp('2026-09-23', tz='UTC') - pd.to_datetime(df['ts'])).dt.days / 365.25
X['lat'], X['lon'] = df['lat'], df['lon']
group = (np.floor(df['lon']) * 1000 + np.floor(df['lat'])).values
tag_cols = [c for c in X.columns if c not in ('ours', 'other')]

stacks = {
    'stack: ours + tags': ['ours'] + tag_cols,
    'stack: SUSformer + tags': ['other'] + tag_cols,
    'stack: ours + SUSformer': ['ours', 'other'],
    'stack: ours + SUSformer + tags': ['ours', 'other'] + tag_cols,
}
preds = {}
for name, cols in stacks.items():
    p = np.zeros(len(df))
    for tr, te in GroupKFold(5).split(X, y, group):
        m = HistGradientBoostingClassifier(max_iter=300, learning_rate=0.05,
                                           categorical_features='from_dtype', random_state=0)
        m.fit(X.iloc[tr][cols], y[tr])
        p[te] = m.predict_proba(X.iloc[te][cols])[:, 1]
    preds[name] = p
    results[name] = report(name, p)

print('\naccuracy vs coverage (most confident first):')
cands = {'ours': pa, 'SUSformer': pb, 'average': (pa + pb) / 2, **preds}
covs = (1.0, 0.95, 0.9, 0.8, 0.7, 0.5)
print(f'{"":34s}' + ''.join(f'{c:>8.0%}' for c in covs))
for name, p in cands.items():
    order = np.argsort(-np.abs(p - 0.5))
    ok = ((p > 0.5) == y)[order]
    print(f'{name:34s}' + ''.join(f'{ok[:int(len(ok) * c)].mean():8.4f}' for c in covs))

print('\naccuracy by OSM surface tag (n >= 30):')
best = preds['stack: ours + SUSformer + tags']
tab = pd.DataFrame({'tag': df['osm_surface'], 'ours': (pa > 0.5) == y, 'SUSformer': (pb > 0.5) == y,
                    'combined': (best > 0.5) == y})
g = tab.groupby('tag')
summary = g.mean().assign(n=g.size())
print(summary[summary['n'] >= 30].sort_values('n', ascending=False).round(4).to_string())

out = df[['osm_id', 'y_true', 'source', 'osm_surface', 'lon', 'lat']].copy()
out['p_ours'], out['p_other'] = pa, pb
for name, p in preds.items():
    out['p_' + name.split(': ')[1].replace(' + ', '_').replace(' ', '')] = p
out.to_csv(out_prefix + '_combined.csv', index=False)
