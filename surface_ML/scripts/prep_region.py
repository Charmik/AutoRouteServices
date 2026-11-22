#!/usr/bin/env python3
""" Common hide-the-tag test set for one region: current OSM ways with a paved/unpaved
    surface tag, split into train/test by spatial cell, balanced per class.

    The surface tag is the label; models only see the imagery (and, for the stackers,
    the other tags). Cells are CELL_DEG squares, a hashed CELL_TEST_SHARE of them go to
    test, so no test road has a training road in the same ~20 km cell.

    Usage: prep_region.py region.geojsonseq region_name out_dir [--n-test 1500] [--n-train 4000]
"""
import argparse
import json
import pathlib
import zlib

import pandas as pd
from tqdm import tqdm

from prep_binary import BINARY_MAP
from prep_features import EXCLUDED_SERVICE, length_m

HIGHWAYS = {'primary', 'secondary', 'tertiary', 'unclassified', 'residential', 'living_street', 'road',
            'service', 'track', 'cycleway', 'path', 'bridleway', 'primary_link', 'secondary_link',
            'tertiary_link'}
TAGS = ['highway', 'tracktype', 'smoothness', 'lanes', 'maxspeed', 'oneway', 'ref', 'name', 'bridge',
        'tunnel', 'service', 'access', 'width', 'lit', 'sidewalk', 'motor_vehicle', 'tiger:cfcc',
        'tiger:reviewed', '4wd_only', 'hgv', 'foot', 'bicycle', 'segregated', 'mtb:scale']
CELL_DEG = 0.2
CELL_TEST_SHARE = 0.25


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('geojsonseq')
    ap.add_argument('region')
    ap.add_argument('out_dir')
    ap.add_argument('--n-test', type=int, default=1500)
    ap.add_argument('--n-train', type=int, default=4000)
    ap.add_argument('--min-length', type=float, default=10.0)
    ap.add_argument('--train-only', help='write only the training sample, to this file name (test set untouched)')
    args = ap.parse_args()

    rows = []
    with open(args.geojsonseq) as f:
        for line in tqdm(f, mininterval=30):
            feat = json.loads(line.lstrip('\x1e'))
            p = feat['properties']
            binary = BINARY_MAP.get(p.get('surface', ''))
            if binary is None or p.get('highway') not in HIGHWAYS or feat['geometry']['type'] != 'LineString':
                continue
            if p.get('area') == 'yes' or p.get('access') == 'private' or p.get('service') in EXCLUDED_SERVICE:
                continue
            coords = feat['geometry']['coordinates']
            length = length_m(coords)
            if length < args.min_length:
                continue
            lon, lat = coords[len(coords) // 2]
            wkt = 'LINESTRING (' + ', '.join(f'{x:.7f} {y:.7f}' for x, y in coords) + ')'
            rows.append({'osm_id': int(p['@id']), 'osm_surface': p['surface'], 'binary': binary,
                         'class_num': int(binary == 'unpaved'), 'wkt': wkt, 'lon': lon, 'lat': lat,
                         'length': round(length, 1), 'ts': p.get('@ts'), 'version': p.get('@ver'),
                         'n_tags': len([k for k in p if not k.startswith('@')]),
                         **{t: p.get(t) for t in TAGS}})
    df = pd.DataFrame(rows).drop_duplicates('osm_id')
    df['region'] = args.region
    cell = (df['lon'] // CELL_DEG).astype(int).astype(str) + '_' + (df['lat'] // CELL_DEG).astype(int).astype(str)
    df['cell'] = cell
    df['split'] = ['test' if zlib.crc32(c.encode()) % 1000 < CELL_TEST_SHARE * 1000 else 'train' for c in cell]
    print(f'{args.region}: {len(df)} tagged ways')
    print(pd.crosstab(df['highway'], df['binary']).to_string())
    print(pd.crosstab(df['split'], df['binary']).to_string())

    out = pathlib.Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    # the region's own paved share, so results can be reweighted to the real mix later
    share = df['binary'].value_counts(normalize=True).to_dict()
    print('natural mix:', share)
    splits = [('train', args.n_train)] if args.train_only else [('test', args.n_test), ('train', args.n_train)]
    for split, n in splits:
        s = df[df['split'] == split]
        s = pd.concat([g.sample(min(len(g), n // 2), random_state=0) for _, g in s.groupby('binary')])
        s = s.sample(frac=1, random_state=0)
        s['paved_share_region'] = share.get('paved', 0)
        s.to_csv(out / (args.train_only or f'{split}.csv'), index=False)
        print(split, s['binary'].value_counts().to_dict())


if __name__ == '__main__':
    main()
