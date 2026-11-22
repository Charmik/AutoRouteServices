#!/usr/bin/env python3
""" Pull the non-surface OSM tags that are known for untagged roads too (highway,
    tracktype, lanes, ...) for the ways in a features CSV, as side information
    for a stacking model on top of the image classifier.

    Usage: osm_tags.py us_surface.geojsonseq features.csv out.csv
"""
import json
import sys

import pandas as pd
from tqdm import tqdm

TAGS = ['highway', 'tracktype', 'smoothness', 'lanes', 'maxspeed', 'oneway', 'ref', 'name',
        'bridge', 'tunnel', 'service', 'access', 'width', 'lit', 'sidewalk', 'motor_vehicle',
        'tiger:cfcc', 'tiger:reviewed', '4wd_only', 'hgv', 'foot', 'bicycle']

src, feats, out = sys.argv[1:4]
ids = set(pd.read_csv(feats, usecols=['osm_id'])['osm_id'])
rows = []
with open(src) as f:
    for line in tqdm(f, mininterval=30):
        feat = json.loads(line.lstrip('\x1e'))
        p = feat['properties']
        i = int(p['@id'])
        if i in ids:
            rows.append({'osm_id': i, 'n_tags': len(p), **{t: p.get(t) for t in TAGS}})
pd.DataFrame(rows).drop_duplicates('osm_id').to_csv(out, index=False)
print(len(rows), 'of', len(ids))
