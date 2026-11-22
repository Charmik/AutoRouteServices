#!/usr/bin/env python3
""" Random sample of OSM ways for the manual check page, same highway filter as
    prep_region.py. 'untagged' = no surface tag (the prediction is new information);
    'tagged' = paved/unpaved surface tag, balanced per class (a held-out test).
    'all' = every way that passes the filter, no sampling (binary empty when untagged or unmapped).
    Reservoir sampling, so it streams country-sized exports.

    Usage: sample_roads.py region_hw.geojsonseq {untagged|tagged|all} out.csv [--n 1500]
"""
import argparse
import json
import random

import pandas as pd

from prep_binary import BINARY_MAP
from prep_features import EXCLUDED_SERVICE, length_m
from prep_region import HIGHWAYS, TAGS

ap = argparse.ArgumentParser()
ap.add_argument('geojsonseq')
ap.add_argument('kind', choices=['untagged', 'tagged', 'all'])
ap.add_argument('out_csv')
ap.add_argument('--n', type=int, default=1500)
ap.add_argument('--min-length', type=float, default=20.0)
args = ap.parse_args()

rng = random.Random(0)
keep = {'paved': [], 'unpaved': [], None: []}
seen = {'paved': 0, 'unpaved': 0, None: 0}
cap = {'paved': args.n // 2, 'unpaved': args.n // 2, None: args.n}
with open(args.geojsonseq) as f:
    for line in f:
        feat = json.loads(line.lstrip('\x1e'))
        p = feat['properties']
        if p.get('highway') not in HIGHWAYS or feat['geometry']['type'] != 'LineString':
            continue
        if p.get('area') == 'yes' or p.get('access') == 'private' or p.get('service') in EXCLUDED_SERVICE:
            continue
        if args.kind == 'untagged':
            if 'surface' in p:
                continue
            key = None
        elif args.kind == 'tagged':
            key = BINARY_MAP.get(p.get('surface', ''))
            if key is None:
                continue
        else:
            key = BINARY_MAP.get(p.get('surface', ''))
        coords = feat['geometry']['coordinates']
        length = length_m(coords)
        if length < args.min_length:
            continue
        seen[key] += 1
        lon, lat = coords[len(coords) // 2]
        row = {'osm_id': int(p['@id']), 'osm_surface': p.get('surface'), 'binary': key,
               'class_num': None if key is None else int(key == 'unpaved'),
               'wkt': 'LINESTRING (' + ', '.join(f'{x:.7f} {y:.7f}' for x, y in coords) + ')',
               'lon': lon, 'lat': lat, 'length': round(length, 1), 'ts': p.get('@ts'),
               **{t: p.get(t) for t in TAGS}}
        if args.kind == 'all':
            keep[key].append(row)
        elif len(keep[key]) < cap[key]:
            keep[key].append(row)
        else:
            j = rng.randrange(seen[key])
            if j < cap[key]:
                keep[key][j] = row
df = pd.DataFrame(keep['paved'] + keep['unpaved'] + keep[None]).sample(frac=1, random_state=0)
if args.kind != 'tagged':
    df['class_num'] = df['class_num'].fillna(0).astype(int)     # placeholder so gis_eval.py runs; not a label
df.to_csv(args.out_csv, index=False)
print(args.kind, len(df), {k: v for k, v in seen.items() if v}, df['highway'].value_counts().to_dict())
