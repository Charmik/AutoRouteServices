#!/usr/bin/env python3
""" Native-resolution NAIP windows along each road, for the GIScience SUSformer model.

    SUSformer looks at a bag of 1-4 square patches spaced along the road (15 m each by
    default, road running up the patch). Here each patch position gets a north-up RGB
    window of WINDOW_M metres at the NAIP item's native resolution, read from the same
    NAIP item our own chip came from. gis_infer.py then cuts rotated patches of any
    size up to WINDOW_M / sqrt(2) out of these windows.

    Patch placement follows SUSformer's materialize.py, minus the junction clearance:
    n = clamp(length // 20 m, 1, 4) positions spread evenly over the middle 80% of the way.

    Usage: gis_fetch.py dataset.csv features.csv fetch_log.csv out_dir [--workers N] [--limit N]
"""
import argparse
import math
import pathlib
import random
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import numpy as np
import pandas as pd
import PIL.Image
from osgeo import gdal, ogr, osr
from tqdm import tqdm

from fetch_chips import http, sas_token

gdal.UseExceptions()
ITEM_URL = 'https://planetarycomputer.microsoft.com/api/stac/v1/collections/naip/items/{}'
WINDOW_M = 60.0
MAX_PATCHES = 4
METERS_PER_PATCH = 20.0
MARGIN = 0.1

_items = {}


def get_item(item_id: str) -> dict:
    if item_id in _items:
        return _items[item_id]
    for attempt in range(10):
        r = http().get(ITEM_URL.format(item_id), timeout=60)
        if r.status_code in (429, 500, 502, 503, 504):
            time.sleep(min(60, 2 ** attempt) * random.uniform(0.5, 1.5))
            continue
        r.raise_for_status()
        _items[item_id] = r.json()
        return _items[item_id]
    r.raise_for_status()


def positions(line, n_max=MAX_PATCHES):
    """ (x, y, bearing_deg) of each patch centre along a projected OGR line """
    pts = np.array([line.GetPoint_2D(i) for i in range(line.GetPointCount())])
    seg = np.hypot(*np.diff(pts, axis=0).T)
    cum = np.concatenate(([0], np.cumsum(seg)))
    length = cum[-1]
    n = int(min(max(length // METERS_PER_PATCH, 1), n_max))
    out = []
    for k in range(n):
        d = length * (MARGIN + (1 - 2 * MARGIN) * (k + 0.5) / n)
        i = min(np.searchsorted(cum, d, side='right') - 1, len(seg) - 1)
        t = (d - cum[i]) / max(seg[i], 1e-9)
        x, y = pts[i] + t * (pts[i + 1] - pts[i])
        dx, dy = pts[i + 1] - pts[i]
        out.append((x, y, math.degrees(math.atan2(dy, dx))))
    return out


def process(row, out_dir: pathlib.Path) -> list:
    item = get_item(row.naip_item)
    props = item['properties']
    epsg = props.get('proj:epsg') or int(str(props['proj:code']).split(':')[-1])
    srs = osr.SpatialReference()
    srs.ImportFromEPSG(epsg)
    srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    wgs84 = osr.SpatialReference()
    wgs84.ImportFromEPSG(4326)
    wgs84.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    line = ogr.CreateGeometryFromWkt(row.wkt)
    line.Transform(osr.CoordinateTransformation(wgs84, srs))

    def open_ds():
        return gdal.Open('/vsicurl/' + item['assets']['image']['href'] + '?' + sas_token())
    try:
        ds = open_ds()
    except RuntimeError as e:
        if '403' not in str(e):
            raise
        sas_token(force=True)
        ds = open_ds()
    gt = ds.GetGeoTransform()
    gsd = gt[1]
    half = int(round(WINDOW_M / gsd / 2))
    rows = []
    for k, (x, y, bearing) in enumerate(positions(line)):
        col, rw = int(round((x - gt[0]) / gt[1])), int(round((y - gt[3]) / gt[5]))
        x0, y0 = col - half, rw - half
        size = 2 * half
        # Clip the read to the raster and pad, so ways near an item edge still work
        cx0, cy0 = max(x0, 0), max(y0, 0)
        cx1, cy1 = min(x0 + size, ds.RasterXSize), min(y0 + size, ds.RasterYSize)
        win = np.zeros((size, size, 3), np.uint8)
        if cx1 > cx0 and cy1 > cy0:
            a = ds.ReadAsArray(cx0, cy0, cx1 - cx0, cy1 - cy0, band_list=[1, 2, 3])
            win[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0] = a.transpose(1, 2, 0)
        path = out_dir / f'{row.osm_id}_{k}.png'
        PIL.Image.fromarray(win).save(path)
        rows.append(dict(osm_id=row.osm_id, k=k, bearing_deg=round(bearing, 2), gsd=gsd, path=str(path)))
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('dataset_csv')
    ap.add_argument('features_csv')
    ap.add_argument('fetch_log')
    ap.add_argument('out_dir')
    ap.add_argument('--workers', type=int, default=12)
    ap.add_argument('--limit', type=int, default=-1)
    args = ap.parse_args()
    out = pathlib.Path(args.out_dir)
    (out / 'windows').mkdir(parents=True, exist_ok=True)
    meta_path = out / 'windows.csv'

    ds = pd.read_csv(args.dataset_csv)
    feats = pd.read_csv(args.features_csv, usecols=['osm_id', 'wkt']).drop_duplicates('osm_id')
    log = pd.read_csv(args.fetch_log)
    log = log[log['status'] == 'ok'].drop_duplicates('osm_id', keep='last')[['osm_id', 'naip_item']]
    df = ds[['osm_id']].merge(feats, on='osm_id').merge(log, on='osm_id')
    if args.limit > 0:
        df = df.iloc[:args.limit]
    done = set(pd.read_csv(meta_path)['osm_id']) if meta_path.exists() else set()
    todo = df[~df['osm_id'].isin(done)]
    print(f'{len(df)} roads, {len(done)} done, {len(todo)} to go')

    write_header = not meta_path.exists()
    n_err = 0
    with open(meta_path, 'a') as f, ThreadPoolExecutor(args.workers) as ex:
        if write_header:
            f.write('osm_id,k,bearing_deg,gsd,path\n')
        futs = {ex.submit(process, r, out / 'windows'): r.osm_id for r in todo.itertuples()}
        for fut in tqdm(as_completed(futs), total=len(futs), mininterval=30):
            try:
                for r in fut.result():
                    f.write(f"{r['osm_id']},{r['k']},{r['bearing_deg']},{r['gsd']},{r['path']}\n")
                f.flush()
            except Exception as e:
                n_err += 1
                if n_err <= 20:
                    print('error', futs[fut], type(e).__name__, str(e)[:200])
    print('errors:', n_err)


if __name__ == '__main__':
    main()
