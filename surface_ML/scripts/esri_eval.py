#!/usr/bin/env python3
""" Score every approach on the common hide-the-tag test, per region.

    Reads <esri>/<region>/test.csv (truth + tags), <esri>/<region>/test/imagery_meta.csv
    and <esri>/pred/<approach>_<region>.csv (osm_id, p_unpaved). For the US it also
    scores the NAIP models on the same roads. Writes <esri>/eval/summary.csv and
    prints the tables.

    Usage: esri_eval.py esri_dir region [region ...]
"""
import pathlib
import sys

import numpy as np
import pandas as pd
from sklearn.ensemble import HistGradientBoostingClassifier
from sklearn.metrics import roc_auc_score
from sklearn.model_selection import GroupKFold

from paths import NAIP, SUS

E = pathlib.Path(sys.argv[1])
REGIONS = sys.argv[2:]
APPROACHES = {
    'zs30': 'Esri: SUSformer as released',
    'naipft': 'Esri: SUSformer tuned on NAIP',
    'esri_release': 'Esri: tuned on Esri (from release)',
    'esri_naipinit': 'Esri: tuned on Esri (from NAIP-tuned)',
    'esri_ens': 'Esri: both Esri-tuned models averaged',
    'esri_r2': 'Esri: tuned on 20k roads per region',
}
NAIP = {
    'naip_maskcnn': (NAIP / 'eval/val_ens_tta.csv', 'NAIP: MaskCNN'),
    'naip_sus': (SUS / 'ft_val.csv', 'NAIP: SUSformer tuned on NAIP'),
}
TAG_COLS = ['highway', 'tracktype', 'smoothness', 'oneway', 'bridge', 'access', 'service', 'lit',
            'sidewalk', 'motor_vehicle', 'bicycle', 'foot']


def recall_at_precision(y_paved, s, target):
    order = np.argsort(-s)
    tp = np.cumsum(y_paved[order])
    prec = tp / np.arange(1, len(s) + 1)
    ok = prec >= target
    return tp[ok].max() / y_paved.sum() if ok.any() else 0.0


def metrics(y, p, share_paved):
    """ y: 1 = unpaved. Accuracy on the balanced test and reweighted to the region's real mix """
    pred = p > 0.5
    ok = pred == y
    acc_p, acc_u = ok[y == 0].mean(), ok[y == 1].mean()
    order = np.argsort(-np.abs(p - 0.5))
    ypav, spav = (y == 0).astype(int), 1 - p
    return {
        'n': len(y),
        'acc': ok.mean(),
        'acc_real_mix': share_paved * acc_p + (1 - share_paved) * acc_u,
        'auc': roc_auc_score(ypav, spav),
        'paved_precision': ((~pred) & (y == 0)).sum() / max((~pred).sum(), 1),
        'paved_recall': acc_p,
        'R@P95': recall_at_precision(ypav, spav, 0.95),
        'R@P99': recall_at_precision(ypav, spav, 0.99),
        'acc@80%cov': ok[order][:int(len(ok) * 0.8)].mean(),
    }


def load_truth(r):
    t = pd.read_csv(E / r / 'test.csv', low_memory=False)
    m = pd.read_csv(E / r / 'test' / 'imagery_meta.csv')
    t = t.merge(m, on='osm_id', how='left')
    if r == 'us':
        tags = pd.read_csv(NAIP / 'eval/osm_tags.csv', low_memory=False)
        t = t.drop(columns=[c for c in tags.columns if c in t.columns and c != 'osm_id']).merge(tags, on='osm_id', how='left')
        meta = pd.read_csv(NAIP / 'eval/way_meta_all.csv', names=['osm_id', 'version', 'ts'])
        t = t.merge(meta, on='osm_id', how='left')
        nat = t[t['source'] == 'natural']
        share = (nat['class_num'] == 0).mean()
    else:
        share = t['paved_share_region'].iloc[0]
    return t, share


def stack(t, p):
    X = pd.DataFrame({'img': np.log(np.clip(p, 1e-6, 1 - 1e-6) / np.clip(1 - p, 1e-6, 1))})
    for c in TAG_COLS:
        X[c] = (t[c] if c in t else pd.Series(index=t.index, dtype=object)).fillna('NA').astype(str).astype('category')
    X['n_tags'] = t.get('n_tags')
    X['has_name'] = t['name'].notna().astype(int) if 'name' in t else 0
    X['lon'], X['lat'] = t['lon'], t['lat']
    group = (np.floor(t['lon'] / 0.2) * 10000 + np.floor(t['lat'] / 0.2)).values
    y = t['class_num'].values
    out = np.zeros(len(t))
    for tr, te in GroupKFold(5).split(X, y, group):
        m = HistGradientBoostingClassifier(max_iter=200, learning_rate=0.05, categorical_features='from_dtype',
                                           random_state=0)
        m.fit(X.iloc[tr], y[tr])
        out[te] = m.predict_proba(X.iloc[te])[:, 1]
    return out


rows, details = [], []
(E / 'eval').mkdir(exist_ok=True)
for r in REGIONS:
    t, share = load_truth(r)
    preds = {}
    for a in APPROACHES:
        f = E / 'pred' / f'{a}_{r}.csv'
        if f.exists():
            preds[a] = pd.read_csv(f)[['osm_id', 'p_unpaved']].rename(columns={'p_unpaved': a})
    if r == 'us':
        for a, (f, _) in NAIP.items():
            preds[a] = pd.read_csv(f)[['osm_id', 'p_unpaved']].rename(columns={'p_unpaved': a})
    for d in preds.values():
        t = t.merge(d, on='osm_id', how='left')
    # common road set: every approach scored it
    have = [a for a in preds]
    t = t.dropna(subset=have).reset_index(drop=True)
    y = t['class_num'].values
    esri = [a for a in APPROACHES if a in preds]
    if esri:
        best = max(esri, key=lambda a: ((t[a] > 0.5) == y).mean())
        t['esri_best+tags'] = stack(t, t[best].values)
        have.append('esri_best+tags')
        if r == 'us':
            t['naip_sus+esri'] = (t['naip_sus'] + t[best]) / 2
            t['naip_sus+esri+tags'] = stack(t, t['naip_sus+esri'].values)
            t['naip_sus+tags'] = stack(t, t['naip_sus'].values)
            have += ['naip_sus+tags', 'naip_sus+esri', 'naip_sus+esri+tags']
    for a in have:
        rows.append({'region': r, 'approach': a, **metrics(y, t[a].values, share)})
    # breakdowns for the best Esri approach
    if esri:
        ok = (t[best] > 0.5) == y
        d = pd.to_datetime(t['src_date'].astype(str), format='%Y%m%d', errors='coerce')
        num = pd.to_numeric(t['ts'], errors='coerce')
        ts = (pd.to_datetime(num, unit='s') if num.notna().all()
              else pd.to_datetime(t['ts'], errors='coerce', utc=True).dt.tz_localize(None))
        t['img_after_edit'] = np.where(d > ts, 'image newer than last edit', 'image older than last edit')
        t['img_year'] = d.dt.year
        for col in ('zoom', 'img_after_edit', 'img_year', 'highway', 'nice_desc'):
            g = pd.DataFrame({'k': t[col].astype(str), 'ok': ok}).groupby('k')['ok']
            s = pd.DataFrame({'acc': g.mean(), 'n': g.size()})
            s = s[s['n'] >= 30]
            for k, v in s.iterrows():
                details.append({'region': r, 'approach': best, 'by': col, 'value': k, 'acc': v['acc'], 'n': int(v['n'])})
        t[['osm_id', 'class_num', 'lon', 'lat', 'highway', 'osm_surface', 'zoom', 'src_date', 'nice_desc'] + have] \
            .to_csv(E / 'eval' / f'scores_{r}.csv', index=False)

res = pd.DataFrame(rows)
res.to_csv(E / 'eval' / 'summary.csv', index=False)
pd.DataFrame(details).to_csv(E / 'eval' / 'breakdown.csv', index=False)
pd.set_option('display.width', 200)
print(res.round(4).to_string(index=False))
print()
print(pd.DataFrame(details).round(4).to_string(index=False))
