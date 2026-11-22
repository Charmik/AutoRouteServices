#!/usr/bin/env python3
""" How many Esri z19 tiles cover a region's OSM ways, by highway group (cumulative).

    A tile counts when it lies within BUFFER_M of the way (the SUSformer windows need a
    few metres either side). Also way length and how much of it already has a surface tag.

    Usage: tile_count.py region_hw.geojsonseq out.csv
"""
import json
import math
import sys

import numpy as np
import pandas as pd

GROUPS = [
    ('main', {'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'motorway_link', 'trunk_link',
              'primary_link', 'secondary_link', 'tertiary_link'}),
    ('minor', {'unclassified', 'residential', 'living_street', 'road'}),
    ('service', {'service'}),
    ('track', {'track'}),
    ('cycle_path', {'cycleway', 'path', 'bridleway'}),
    ('foot', {'footway', 'pedestrian', 'steps'}),
]
Z = 19
BUFFER_M = 15.0
STEP_M = 5.0

src, out = sys.argv[1:3]
group_of = {h: g for g, hs in GROUPS for h in hs}
tiles = {g: [] for g, _ in GROUPS}
stats = {g: dict(ways=0, km=0.0, km_tagged=0.0) for g, _ in GROUPS}
n = 2 ** Z
with open(src) as f:
    for line in f:
        feat = json.loads(line.lstrip('\x1e'))
        p = feat['properties']
        g = group_of.get(p.get('highway'))
        if g is None or feat['geometry']['type'] != 'LineString':
            continue
        c = np.array(feat['geometry']['coordinates'])
        lat0 = math.radians(c[:, 1].mean())
        k = math.cos(lat0) * 111_320
        xy = np.column_stack([c[:, 0] * k, c[:, 1] * 111_320])
        seg = np.hypot(*np.diff(xy, axis=0).T)
        length = seg.sum()
        stats[g]['ways'] += 1
        stats[g]['km'] += length / 1000
        if 'surface' in p:
            stats[g]['km_tagged'] += length / 1000
        # points every STEP_M along the way, plus the corners of a BUFFER_M square around each
        pts = [xy[:1]]
        for a, b, s in zip(xy[:-1], xy[1:], seg):
            m = max(int(s // STEP_M), 1)
            pts.append(a + (b - a) * (np.arange(1, m + 1)[:, None] / m))
        pts = np.concatenate(pts)
        offs = np.array([[0, 0], [BUFFER_M, BUFFER_M], [BUFFER_M, -BUFFER_M], [-BUFFER_M, BUFFER_M], [-BUFFER_M, -BUFFER_M]])
        allp = (pts[:, None, :] + offs[None]).reshape(-1, 2)
        lon, lat = allp[:, 0] / k, allp[:, 1] / 111_320
        tx = ((lon + 180) / 360 * n).astype(np.int64)
        ty = ((1 - np.arcsinh(np.tan(np.radians(lat))) / np.pi) / 2 * n).astype(np.int64)
        tiles[g].append(np.unique(tx * n + ty))

rows, seen = [], np.array([], np.int64)
for g, _ in GROUPS:
    t = np.unique(np.concatenate(tiles[g])) if tiles[g] else np.array([], np.int64)
    seen = np.union1d(seen, t)
    rows.append(dict(group=g, **stats[g], tiles_group=len(t), tiles_cumulative=len(seen)))
df = pd.DataFrame(rows)
df['km_cumulative'] = df['km'].cumsum()
df.to_csv(out, index=False)
print(df.round(1).to_string(index=False))
