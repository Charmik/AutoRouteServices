#!/usr/bin/env python3
""" Paved/unpaved feature list: every feature from the 8-class run (chips already
    fetched) relabeled to paved/unpaved, plus new ways sampled in proportion to
    how common each surface tag is in the US, including the generic 'paved' /
    'unpaved' tags that the 8-class run had to skip.

    Usage: prep_binary.py us_surface.geojsonseq old_features.csv out_csv [--new-per-class N]
"""
import argparse
import json

import pandas as pd
from tqdm import tqdm

from prep_features import EXCLUDED_SERVICE, length_m

BINARY_MAP = {
    'asphalt': 'paved', 'concrete': 'paved', 'concrete:plates': 'paved',
    'concrete:lanes': 'paved', 'paved': 'paved', 'chipseal': 'paved',
    'paving_stones': 'paved', 'bricks': 'paved', 'brick': 'paved', 'sett': 'paved',
    'cobblestone': 'paved',
    'unpaved': 'unpaved', 'gravel': 'unpaved', 'fine_gravel': 'unpaved',
    'compacted': 'unpaved', 'dirt': 'unpaved', 'earth': 'unpaved', 'ground': 'unpaved',
    'dirt/sand': 'unpaved', 'sand': 'unpaved', 'grass': 'unpaved', 'mud': 'unpaved',
    'pebblestone': 'unpaved', 'rock': 'unpaved', 'unhewn_cobblestone': 'unpaved',
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('geojsonseq')
    ap.add_argument('old_features_csv')
    ap.add_argument('out_csv')
    ap.add_argument('--new-per-class', type=int, default=10500)
    ap.add_argument('--min-length', type=float, default=10.0)
    args = ap.parse_args()

    old = pd.read_csv(args.old_features_csv)
    old['binary'] = old['osm_surface'].map(BINARY_MAP)
    old['source'] = 'v1'
    old_ids = set(old['osm_id'])

    rows = []
    with open(args.geojsonseq) as f:
        for line in tqdm(f, mininterval=10):
            feat = json.loads(line.lstrip('\x1e'))
            p = feat['properties']
            binary = BINARY_MAP.get(p.get('surface', ''))
            if binary is None or int(p['@id']) in old_ids:
                continue
            if (p.get('area') == 'yes' or p.get('access') == 'private'
                    or p.get('motor_vehicle') == 'no' or p.get('motorcar') == 'no'
                    or p.get('service') in EXCLUDED_SERVICE):
                continue
            coords = feat['geometry']['coordinates']
            length = length_m(coords)
            if length < args.min_length:
                continue
            lon, lat = coords[len(coords) // 2]
            wkt = 'LINESTRING (' + ', '.join(f'{x:.7f} {y:.7f}' for x, y in coords) + ')'
            rows.append((int(p['@id']), p['surface'], p['surface'], p.get('highway', ''), wkt,
                         lon, lat, round(length, 1), binary))

    new = pd.DataFrame(rows, columns=['osm_id', 'osm_surface', 'surface', 'highway', 'wkt',
                                      'lon', 'lat', 'length', 'binary'])
    new = new.drop_duplicates('osm_id')
    # Uniform sample within each binary class = proportional to tag frequency
    new = pd.concat([g.sample(min(len(g), args.new_per_class), random_state=7)
                     for _, g in new.groupby('binary')])
    new['source'] = 'natural'
    print('New sample:')
    print(new.groupby(['binary', 'osm_surface']).size().sort_values(ascending=False).to_string())

    df = pd.concat([old, new]).sample(frac=1, random_state=42).reset_index(drop=True)
    print('\nTotal:')
    print(df.groupby(['binary', 'source']).size().to_string())
    df.to_csv(args.out_csv, index=False)


if __name__ == '__main__':
    main()
