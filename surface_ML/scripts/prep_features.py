#!/usr/bin/env python3
""" Turn the osmium GeoJSONSeq export of US drivable ways with a surface tag into
    features.csv (osm_id, surface, highway, wkt, lon, lat, length).

    Mirrors scripts/perform_query.py's Overpass filters and notebook 02's
    filtering / per-class capping.

    Usage: prep_features.py us_surface.geojsonseq features.csv [--per-class N]
"""
import argparse
import json
import math

import numpy as np
import pandas as pd
from tqdm import tqdm

# Notebook 02 multiclass map (generic 'paved' / 'unpaved' are excluded there too)
CLASS_MAP = {
    'asphalt': 'asphalt',
    'bricks': 'bricks',
    'concrete': 'concrete',
    'concrete:plates': 'concrete',
    'paving_stones': 'paving_stones',
    'compacted': 'compacted',
    'dirt': 'dirt',
    'gravel': 'gravel',
    'ground': 'ground',
}
EXCLUDED_SERVICE = {
    'alley', 'driveway', 'emergency_access', 'parking', 'parking_aisle', 'private'
}


def length_m(coords) -> float:
    """ Equirectangular approximation, fine for short ways """
    total = 0.0
    for (x1, y1), (x2, y2) in zip(coords[:-1], coords[1:]):
        k = math.cos(math.radians((y1 + y2) / 2))
        total += math.hypot((x2 - x1) * k, y2 - y1) * 111_320
    return total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('geojsonseq')
    ap.add_argument('out_csv')
    ap.add_argument('--per-class', type=int, default=5000)
    ap.add_argument('--min-length', type=float, default=10.0)
    args = ap.parse_args()

    rows = []
    with open(args.geojsonseq) as f:
        for line in tqdm(f, mininterval=10):
            feat = json.loads(line.lstrip('\x1e'))
            p = feat['properties']
            surface = CLASS_MAP.get(p.get('surface', ''))
            if surface is None:
                continue
            if (p.get('area') == 'yes' or p.get('access') == 'private'
                    or p.get('motor_vehicle') == 'no' or p.get('motorcar') == 'no'
                    or p.get('service') in EXCLUDED_SERVICE):
                continue
            coords = feat['geometry']['coordinates']
            length = length_m(coords)
            if length < args.min_length:
                continue
            lon, lat = coords[len(coords) // 2]     # middle vertex, as in notebook 02
            wkt = 'LINESTRING (' + ', '.join(f'{x:.7f} {y:.7f}' for x, y in coords) + ')'
            rows.append((int(p['@id']), p['surface'], surface, p.get('highway', ''), wkt,
                         lon, lat, round(length, 1)))

    df = pd.DataFrame(rows, columns=['osm_id', 'osm_surface', 'surface', 'highway', 'wkt',
                                     'lon', 'lat', 'length'])
    df = df.drop_duplicates('osm_id')
    print('All matching ways by class:')
    print(df['surface'].value_counts().to_string())

    # Shuffle, then cap each class (notebook 02 used 5000)
    df = df.sample(frac=1, random_state=42).reset_index(drop=True)
    df = pd.concat([g.iloc[:args.per_class] for _, g in df.groupby('surface')])
    df = df.sample(frac=1, random_state=42).reset_index(drop=True)
    print('\nAfter per-class cap:')
    print(df['surface'].value_counts().to_string())
    df.to_csv(args.out_csv, index=False)


if __name__ == '__main__':
    main()
