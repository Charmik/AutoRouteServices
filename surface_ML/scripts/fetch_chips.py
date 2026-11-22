#!/usr/bin/env python3
""" Fetch 256x256 m NAIP chips (1 m/px, R-G-B-NIR) centered on OSM ways, plus the
    2 px way mask, from Microsoft Planetary Computer NAIP COGs.

    Stand-in for notebook 02's NAIP-on-AWS (requester pays) download + chipping.

    Usage: fetch_chips.py features.csv out_dir [--workers N] [--limit N]
"""
import argparse
import pathlib
import threading
import random
import time
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed

import numpy as np
import pandas as pd
import PIL.Image
import PIL.ImageDraw
import requests
from osgeo import gdal, ogr, osr
from tqdm import tqdm

gdal.UseExceptions()
ogr.UseExceptions()
for k, v in {
        'GDAL_DISABLE_READDIR_ON_OPEN': 'EMPTY_DIR',
        'CPL_VSIL_CURL_ALLOWED_EXTENSIONS': '.tif',
        'GDAL_HTTP_MULTIRANGE': 'YES',
        'GDAL_HTTP_MERGE_CONSECUTIVE_RANGES': 'YES',
        'GDAL_HTTP_MAX_RETRY': '5',
        'GDAL_HTTP_RETRY_DELAY': '2',
        'VSI_CACHE': 'FALSE',
}.items():
    gdal.SetConfigOption(k, v)

STAC_SEARCH = 'https://planetarycomputer.microsoft.com/api/stac/v1/search'
SAS_URL = 'https://planetarycomputer.microsoft.com/api/sas/v1/token/naip'
CHIP = 256          # pixels == meters at 1 m/px
MIN_YEAR = 2018     # skip very old imagery

_session = threading.local()
_token = {'value': None, 'expires': 0.0}
_token_lock = threading.Lock()


def http() -> requests.Session:
    if not hasattr(_session, 's'):
        _session.s = requests.Session()
    return _session.s


def sas_token(force: bool = False) -> str:
    """ The SAS endpoint hands out a shared token that may be close to expiry:
        refresh 5 minutes before its stated msft:expiry """
    with _token_lock:
        if force or time.time() > _token['expires']:
            for attempt in range(10):
                r = requests.get(SAS_URL, timeout=30)
                if r.status_code == 200:
                    break
                time.sleep(min(60, 2 ** attempt))
            r.raise_for_status()
            d = r.json()
            _token['value'] = d['token']
            expiry = datetime.fromisoformat(d['msft:expiry'].replace('Z', '+00:00')).timestamp()
            _token['expires'] = max(time.time() + 30, expiry - 5 * 60)
        return _token['value']


def find_items(lon: float, lat: float) -> list:
    """ Newest-first NAIP items whose footprint contains the point """
    body = {
        'collections': ['naip'],
        'intersects': {'type': 'Point', 'coordinates': [lon, lat]},
        'datetime': f'{MIN_YEAR}-01-01T00:00:00Z/..',
        'sortby': [{'field': 'properties.datetime', 'direction': 'desc'}],
        'limit': 3,
    }
    for attempt in range(10):
        r = http().post(STAC_SEARCH, json=body, timeout=60)
        if r.status_code in (429, 500, 502, 503, 504):
            time.sleep(min(60, 2 ** attempt) * random.uniform(0.5, 1.5))
            continue
        r.raise_for_status()
        return r.json()['features']
    r.raise_for_status()
    return []


def warp_chip(item: dict, lon: float, lat: float, out_path: pathlib.Path):
    """ Warp a 256x256 1 m chip centered on lon/lat in the item's native UTM CRS """
    props = item['properties']
    epsg = props.get('proj:epsg') or int(str(props['proj:code']).split(':')[-1])
    srs = osr.SpatialReference()
    srs.ImportFromEPSG(epsg)
    srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    wgs84 = osr.SpatialReference()
    wgs84.ImportFromEPSG(4326)
    wgs84.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    cx, cy, _ = osr.CoordinateTransformation(wgs84, srs).TransformPoint(lon, lat)
    cx, cy = round(cx), round(cy)
    href = item['assets']['image']['href'] + '?' + sas_token()
    gdal.Warp(str(out_path),
              '/vsicurl/' + href,
              dstSRS=f'EPSG:{epsg}',
              outputBounds=(cx - CHIP // 2, cy - CHIP // 2, cx + CHIP // 2, cy + CHIP // 2),
              xRes=1.0,
              yRes=1.0,
              resampleAlg='average',
              format='GTiff',
              creationOptions=['COMPRESS=DEFLATE', 'PREDICTOR=2'])
    return srs


def draw_mask(wkt: str, chip_path: pathlib.Path, srs: osr.SpatialReference,
              out_path: pathlib.Path, width: int = 2):
    """ Same line mask as notebook 02 (2 px wide, curved joints) """
    ds = gdal.Open(str(chip_path))
    xf = ds.GetGeoTransform()
    w, h = ds.RasterXSize, ds.RasterYSize
    ds = None
    wgs84 = osr.SpatialReference()
    wgs84.ImportFromEPSG(4326)
    wgs84.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    geom = ogr.CreateGeometryFromWkt(wkt)
    geom.Transform(osr.CoordinateTransformation(wgs84, srs))
    pts = [geom.GetPoint_2D(i) for i in range(geom.GetPointCount())]
    pix = [((x - xf[0]) / xf[1], (y - xf[3]) / xf[5]) for x, y in pts]
    mask = PIL.Image.new('L', (w, h), color=0)
    PIL.ImageDraw.Draw(mask).line(pix, fill=255, width=width, joint='curve')
    mask.save(out_path, format='PNG')


def process(row, img_dir: pathlib.Path, mask_dir: pathlib.Path) -> dict:
    osm_id = int(row.osm_id)
    chip_path = img_dir / f'{osm_id}.tif'
    mask_path = mask_dir / f'{osm_id}.png'
    res = dict(osm_id=osm_id, status='ok', naip_item='', naip_date='')
    try:
        items = find_items(row.lon, row.lat)
        if not items:
            res['status'] = 'no_naip'
            return res
        for item in items:
            tmp = chip_path.with_suffix('.part.tif')
            try:
                srs = warp_chip(item, row.lon, row.lat, tmp)
            except RuntimeError as e:
                if '403' not in str(e):
                    raise
                sas_token(force=True)     # expired / revoked token: refresh and retry once
                srs = warp_chip(item, row.lon, row.lat, tmp)
            im = gdal.Open(str(tmp)).ReadAsArray()
            # Reject chips touching the image edge / nodata (all bands zero)
            if im.shape[0] < 4 or (im.max(axis=0) == 0).mean() > 0.01:
                tmp.unlink()
                continue
            # gdal.Warp ignores the ALPHA=YES creation option. Tag band 4 (NIR) as
            # alpha so PIL, which the training dataset uses, loads all 4 bands (RGBA)
            ds = gdal.Open(str(tmp), gdal.GA_Update)
            ds.GetRasterBand(4).SetColorInterpretation(gdal.GCI_AlphaBand)
            ds = None
            tmp.rename(chip_path)
            draw_mask(row.wkt, chip_path, srs, mask_path)
            res['naip_item'] = item['id']
            res['naip_date'] = item['properties']['datetime'][:10]
            return res
        res['status'] = 'nodata'
    except Exception as e:     # keep going; record the failure
        res['status'] = f'error: {type(e).__name__}: {str(e)[:200]}'
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('features_csv')
    ap.add_argument('out_dir')
    ap.add_argument('--workers', type=int, default=12)
    ap.add_argument('--limit', type=int, default=-1)
    args = ap.parse_args()

    out = pathlib.Path(args.out_dir)
    img_dir, mask_dir = out / 'imagery', out / 'masks'
    img_dir.mkdir(parents=True, exist_ok=True)
    mask_dir.mkdir(parents=True, exist_ok=True)
    log_path = out / 'fetch_log.csv'

    df = pd.read_csv(args.features_csv)
    if args.limit > 0:
        df = df.iloc[:args.limit]
    # Resume: skip anything already attempted, except errors (retried)
    done = set()
    if log_path.exists():
        log_df = pd.read_csv(log_path)
        done = set(log_df.loc[~log_df['status'].str.startswith('error'), 'osm_id'])
    todo = df[~df['osm_id'].isin(done)]
    print(f'{len(df)} features, {len(done)} already attempted, {len(todo)} to go')

    write_header = not log_path.exists()
    with open(log_path, 'a') as log, ThreadPoolExecutor(args.workers) as ex:
        if write_header:
            log.write('osm_id,status,naip_item,naip_date\n')
        futs = [ex.submit(process, r, img_dir, mask_dir) for r in todo.itertuples()]
        n_ok = 0
        for f in tqdm(as_completed(futs), total=len(futs), mininterval=10):
            r = f.result()
            n_ok += r['status'] == 'ok'
            status = r['status'].replace(',', ';').replace('\n', ' ')
            log.write(f"{r['osm_id']},{status},{r['naip_item']},{r['naip_date']}\n")
            log.flush()
    print(f'done: {n_ok} ok of {len(futs)}')


if __name__ == '__main__':
    main()
