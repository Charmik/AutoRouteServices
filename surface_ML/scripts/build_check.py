#!/usr/bin/env python3
""" Data for the manual check page: roads.json plus sprite sheets of the 30 m Esri patch
    the model saw at the middle of each road (road running up).

    Usage: build_check.py out_dir [samples|cy_all]
      samples: 1500-road test/untagged samples for CY, DE, US
      cy_all:  every Cyprus way, set = tagged/untagged from its OSM surface tag
"""
import json
import math
import pathlib
import sys

import numpy as np
import pandas as pd
import PIL.Image

from gis_train import cut_patch
from paths import ESRI, NAIP, SUS

E = ESRI
C = E / 'check'
OUT = pathlib.Path(sys.argv[1])
MODE = sys.argv[2] if len(sys.argv) > 2 else 'samples'
(OUT / 'sheets').mkdir(parents=True, exist_ok=True)
PX, PER_ROW = 128, 10
PER_SHEET = PER_ROW * PER_ROW
US_TEST_N = 1500
MAXPTS, ND = (16, 5) if MODE == 'cy_all' else (40, 6)     # keep the whole-island json small

# (country, set, roads csv, windows dir, Esri prediction csv)
SETS = [
    ('CY', 'test', C / 'cy_test.csv', C / 'cy_test', C / 'pred_cy_test.csv'),
    ('CY', 'untagged', C / 'cy_untagged.csv', C / 'cy_untagged', C / 'pred_cy_untagged.csv'),
    ('DE', 'test', E / 'de_bavaria/test.csv', E / 'de_bavaria/test', E / 'pred/esri_r2_de_bavaria.csv'),
    ('DE', 'untagged', C / 'de_untagged.csv', C / 'de_untagged', C / 'pred_de_untagged.csv'),
    ('US', 'test', E / 'us/test.csv', E / 'us/test', E / 'pred/esri_r2_us.csv'),
    ('US', 'untagged', C / 'us_untagged.csv', C / 'us_untagged', C / 'pred_us_untagged.csv'),
]
if MODE == 'cy_all':
    SETS = [('CY', 'all', C / 'cy_all.csv', C / 'cy_all', C / 'pred_cy_all.csv')]
naip = pd.read_csv(SUS / 'ft_val.csv').set_index('osm_id')['p_unpaved']
us_tags = pd.read_csv(NAIP / 'eval/osm_tags.csv', usecols=['osm_id', 'name'], low_memory=False).set_index('osm_id')['name']


def coords(wkt):
    pts = [tuple(map(float, p.split())) for p in wkt[wkt.index('(') + 1:-1].split(',')]
    if len(pts) > MAXPTS:     # thin long ways, keep ends
        idx = np.unique(np.linspace(0, len(pts) - 1, MAXPTS).round().astype(int))
        pts = [pts[i] for i in idx]
    return [[round(x, ND), round(y, ND)] for x, y in pts]


def clean(v):
    return None if v is None or (isinstance(v, float) and math.isnan(v)) else v


roads, sheet, sheet_n, n_sheet = [], None, 0, 0


def add_crop(img):
    global sheet, sheet_n, n_sheet
    if sheet is None:
        sheet = PIL.Image.new('RGB', (PX * PER_ROW, PX * PER_ROW), (200, 200, 200))
    sheet.paste(img, ((sheet_n % PER_ROW) * PX, (sheet_n // PER_ROW) * PX))
    ref = [n_sheet, sheet_n]
    sheet_n += 1
    if sheet_n == PER_SHEET:
        flush()
    return ref


def flush():
    global sheet, sheet_n, n_sheet
    if sheet is not None:
        sheet.save(OUT / 'sheets' / f'{n_sheet}.jpg', quality=80)
        sheet, sheet_n, n_sheet = None, 0, n_sheet + 1


stats = []
for country, s, roads_csv, win_dir, pred_csv in SETS:
    if not pred_csv.exists():
        print('not ready yet:', country, s)
        continue
    t = pd.read_csv(roads_csv, low_memory=False)
    if country == 'US' and s == 'test':
        t = t.sample(US_TEST_N, random_state=0)
    pred = pd.read_csv(pred_csv)[['osm_id', 'p_unpaved']]
    meta = pd.read_csv(win_dir / 'imagery_meta.csv')
    wins = pd.read_csv(win_dir / 'windows.csv')
    t = t.merge(pred, on='osm_id').merge(meta[['osm_id', 'zoom', 'src_date', 'nice_desc']], on='osm_id', how='left')
    groups = dict(tuple(wins.groupby('osm_id')))
    for r in t.itertuples():
        g = groups.get(r.osm_id)
        im = None
        if g is not None:
            w = g.iloc[len(g) // 2]
            crop = cut_patch(PIL.Image.open(w.path).convert('RGB'), w.gsd, w.bearing_deg, 30.0, PX)
            im = add_crop(crop)
        name = getattr(r, 'name', None)
        if country == 'US' and s == 'test':
            name = us_tags.get(r.osm_id)
        tagged = s == 'test' or (s == 'all' and not pd.isna(r.binary))
        sset = s if s != 'all' else ('tagged' if tagged else 'untagged')
        rec = {
            'id': int(r.osm_id), 'c': country, 's': sset, 'k': r.highway, 'nm': clean(name),
            'sf': clean(r.osm_surface) if s in ('test', 'all') else None,
            'y': (1 - int(r.class_num)) if tagged else None,     # 1 = paved
            'ps': round(1 - float(r.p_unpaved), 3),
            'pn': round(1 - float(naip[r.osm_id]), 3) if country == 'US' and s == 'test' and r.osm_id in naip.index else None,
            'g': coords(r.wkt), 'im': im,
            'z': None if pd.isna(r.zoom) else int(r.zoom),
            'd': None if pd.isna(r.src_date) else str(int(r.src_date)),
            'src': clean(r.nice_desc),
        }
        if MODE == 'cy_all':
            rec = {k: v for k, v in rec.items() if v is not None and k != 'c'}
            rec['c'] = country     # the page needs it; nulls dropped to keep 147k ways light
        roads.append(rec)
    stats.append((country, s, len(t)))
flush()
json.dump({'countries': {'CY': 'Cyprus', 'DE': 'Germany (Bavaria)', 'US': 'United States'}, 'roads': roads},
          open(OUT / 'roads.json', 'w'), separators=(',', ':'))
print(stats, 'sheets', n_sheet, 'json MB', round((OUT / 'roads.json').stat().st_size / 1e6, 1))
