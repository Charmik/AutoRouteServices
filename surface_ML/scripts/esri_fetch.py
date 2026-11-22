#!/usr/bin/env python3
""" Esri World Imagery windows along each road, in the same layout as gis_fetch.py
    (north-up RGB windows of WINDOW_M metres at each SUSformer patch position), so
    gis_train.py / gis_eval.py run on them unchanged.

    Tiles come from the live World Imagery tile service at the highest zoom that has
    real data for the window (z19, else z18, else z17); Esri serves a fixed grey
    "not available" tile where a zoom is missing. Per road we also record the capture
    date and source of the imagery at that zoom from the World Imagery metadata layer.

    Every request is retried with backoff (honouring Retry-After on 429/503). A road whose
    tiles or metadata still fail is not marked done: it goes to out_dir/fetch_errors.csv and
    is tried again in up to --passes passes at the end, and by any rerun. HTTP status and
    retry counts are printed every few minutes and at the end; the exit code is 1 if any
    road is still failing.

    Raw tiles are kept in a shared cache, TILE_DIR/{z}/{x}/{y}.jpg (a {y}.missing marker for
    Esri's "not available" tile), and read from there instead of downloaded when present, so
    reruns with other window sizes or models need no network. --tiles-only fills the cache
    for roads already done (no windows or metadata written).

    Usage: esri_fetch.py roads.csv out_dir [--workers 12] [--limit N] [--passes 3]
             [--tile-dir DIR] [--tiles-only] [--shard i/n]
           --shard i/n: only roads with osm_id % n == i, written to windows.i.csv /
             imagery_meta.i.csv / fetch_errors.i.csv so n processes can share out_dir;
             esri_fetch.py --merge out_dir folds them into windows.csv / imagery_meta.csv.
             roads.csv: osm_id, wkt (WGS84 LINESTRING), lon, lat
"""
import argparse
import collections
import sys
import hashlib
import io
import math
import pathlib
import random
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import numpy as np
import pandas as pd
import PIL.Image
import requests
from tqdm import tqdm

from paths import ESRI
from gis_fetch import MARGIN, MAX_PATCHES, METERS_PER_PATCH, WINDOW_M

TILE_URL = 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
META_URL = ('https://metadata.maptiles.arcgis.com/arcgis/rest/services/World_Imagery_Metadata_2026_r10/'
            'MapServer/identify')
MISSING_MD5 = 'f27d9de7f80c13501f470595e327aa6d'
META_LAYER = {19: 4, 18: 5, 17: 6}     # metadata layer drawn at each zoom
EARTH = 2 * math.pi * 6378137.0
_local = threading.local()
TILE_DIR = ESRI / 'tiles'
_stats_lock = threading.Lock()
STATS = collections.Counter()     # 'http_<code>', 'retry', 'conn_error', 'timeout', 'gave_up'
RETRIES = 8


def count(key):
    with _stats_lock:
        STATS[key] += 1


def http():
    if not hasattr(_local, 's'):
        _local.s = requests.Session()
        _local.s.headers['User-Agent'] = 'road-surface-eval/0.1'
    return _local.s


def get(url, **kw):
    for attempt in range(RETRIES):
        wait = min(60, 2 ** attempt) * random.uniform(0.5, 1.5)
        try:
            r = http().get(url, timeout=60, **kw)
            count(f'http_{r.status_code}')
            if r.status_code in (429, 500, 502, 503, 504):
                ra = r.headers.get('Retry-After', '')
                if ra.isdigit():
                    wait = max(wait, min(300, int(ra)))
                raise requests.HTTPError(f'HTTP {r.status_code}', response=r)
            r.raise_for_status()
            return r
        except (requests.ConnectionError, requests.Timeout, requests.HTTPError) as e:
            count('timeout' if isinstance(e, requests.Timeout) else 'conn_error' if isinstance(e, requests.ConnectionError) else 'http_error')
            if attempt == RETRIES - 1:
                count('gave_up')
                raise RuntimeError(f'{type(e).__name__} {e} after {RETRIES} tries: {url}') from e
            count('retry')
            time.sleep(wait)


def disk_tile(z, x, y):
    """ bytes of the tile from the disk cache, downloading and saving it only if absent; None = missing """
    d = TILE_DIR / str(z) / str(x)
    f, miss = d / f'{y}.jpg', d / f'{y}.missing'
    if f.exists():
        count('tile_disk')
        return f.read_bytes()
    if miss.exists():
        count('tile_disk')
        return None
    b = get(TILE_URL.format(z=z, y=y, x=x)).content
    count('tile_net')
    d.mkdir(parents=True, exist_ok=True)
    if hashlib.md5(b).hexdigest() == MISSING_MD5:
        miss.touch()
        return None
    tmp = d / f'{y}.{threading.get_ident()}.tmp'     # atomic: other threads never see half a tile
    tmp.write_bytes(b)
    tmp.replace(f)
    return b


def tile(z, x, y, cache):
    key = (z, x, y)
    if key not in cache:
        b = disk_tile(z, x, y)
        cache[key] = None if b is None else np.asarray(PIL.Image.open(io.BytesIO(b)).convert('RGB'))
    return cache[key]


def world_px(lon, lat, z):
    n = 256 * 2 ** z
    return (lon + 180) / 360 * n, (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n


def window(lon, lat, z, cache):
    """ north-up WINDOW_M window centred on lon/lat at zoom z, or None if any tile is missing """
    gsd = EARTH / (256 * 2 ** z) * math.cos(math.radians(lat))
    half = int(round(WINDOW_M / gsd / 2))
    px, py = world_px(lon, lat, z)
    x0, y0 = int(round(px)) - half, int(round(py)) - half
    size = 2 * half
    out = np.zeros((size, size, 3), np.uint8)
    for ty in range(y0 // 256, (y0 + size - 1) // 256 + 1):
        for tx in range(x0 // 256, (x0 + size - 1) // 256 + 1):
            t = tile(z, tx, ty, cache)
            if t is None:
                return None, gsd
            ax0, ay0 = max(x0, tx * 256), max(y0, ty * 256)
            ax1, ay1 = min(x0 + size, tx * 256 + 256), min(y0 + size, ty * 256 + 256)
            out[ay0 - y0:ay1 - y0, ax0 - x0:ax1 - x0] = t[ay0 - ty * 256:ay1 - ty * 256, ax0 - tx * 256:ax1 - tx * 256]
    return out, gsd


def positions(coords):
    """ (lon, lat, bearing_deg) of each patch centre, same placement as gis_fetch.positions """
    lat0 = coords[len(coords) // 2][1]
    k = math.cos(math.radians(lat0)) * 111_320
    pts = np.array([(x * k, y * 111_320) for x, y in coords])
    seg = np.hypot(*np.diff(pts, axis=0).T)
    cum = np.concatenate(([0], np.cumsum(seg)))
    length = cum[-1]
    n = int(min(max(length // METERS_PER_PATCH, 1), MAX_PATCHES))
    out = []
    for j in range(n):
        d = length * (MARGIN + (1 - 2 * MARGIN) * (j + 0.5) / n)
        i = min(np.searchsorted(cum, d, side='right') - 1, len(seg) - 1)
        t = (d - cum[i]) / max(seg[i], 1e-9)
        x, y = pts[i] + t * (pts[i + 1] - pts[i])
        dx, dy = pts[i + 1] - pts[i]
        out.append((x / k, y / 111_320, math.degrees(math.atan2(dy, dx))))
    return out


def capture_meta(lon, lat, z):
    params = dict(geometry=f'{lon},{lat}', geometryType='esriGeometryPoint', sr=4326,
                  layers=f'all:{META_LAYER[z]}', tolerance=0, returnGeometry='false', f='json',
                  mapExtent=f'{lon - .01},{lat - .01},{lon + .01},{lat + .01}', imageDisplay='256,256,96')
    res = get(META_URL, params=params).json().get('results', [])     # a failure fails the road, so it is retried
    for r in res:
        if r['layerId'] == META_LAYER[z]:
            a = r['attributes']
            return dict(src_date=a.get('SRC_DATE'), src_res=a.get('SRC_RES'), src_desc=a.get('SRC_DESC'),
                        nice_desc=a.get('NICE_DESC'), nice_name=a.get('NICE_NAME'))
    return {}


def tiles_only(row):
    """ fill the tile cache for a road with the same zoom fallback as process(), save nothing else """
    coords = [tuple(map(float, p.split())) for p in row.wkt[row.wkt.index('(') + 1:-1].split(',')]
    cache = {}
    for lon, lat, _ in positions(coords):
        for z in (19, 18, 17):
            if window(lon, lat, z, cache)[0] is not None:
                break


def process(row, out_dir: pathlib.Path):
    coords = [tuple(map(float, p.split())) for p in row.wkt[row.wkt.index('(') + 1:-1].split(',')]
    cache, rows, zooms = {}, [], []
    for k, (lon, lat, bearing) in enumerate(positions(coords)):
        for z in (19, 18, 17):
            win, gsd = window(lon, lat, z, cache)
            if win is not None:
                break
        if win is None:
            continue
        path = out_dir / f'{row.osm_id}_{k}.jpg'
        PIL.Image.fromarray(win).save(path, quality=95)
        rows.append(dict(osm_id=row.osm_id, k=k, bearing_deg=round(bearing, 2), gsd=round(gsd, 4),
                         path=str(path), zoom=z))
        zooms.append(z)
    meta = dict(osm_id=row.osm_id, zoom=min(zooms) if zooms else None, n_windows=len(rows))
    if zooms:
        meta.update(capture_meta(row.lon, row.lat, meta['zoom']))
    return rows, meta


def main():
    ap = argparse.ArgumentParser()
    if sys.argv[1:2] == ['--merge']:
        return merge(pathlib.Path(sys.argv[2]))
    ap.add_argument('roads_csv')
    ap.add_argument('out_dir')
    ap.add_argument('--shard', default=None)
    ap.add_argument('--workers', type=int, default=12)
    ap.add_argument('--limit', type=int, default=-1)
    ap.add_argument('--passes', type=int, default=3)
    ap.add_argument('--tile-dir', default=None)
    ap.add_argument('--tiles-only', action='store_true')
    args = ap.parse_args()
    global TILE_DIR
    if args.tile_dir:
        TILE_DIR = pathlib.Path(args.tile_dir)
    out = pathlib.Path(args.out_dir)
    (out / 'windows').mkdir(parents=True, exist_ok=True)
    sfx = ''
    if args.shard:
        si, sn = map(int, args.shard.split('/'))
        sfx = f'.{si}'
    win_path, meta_path = out / f'windows{sfx}.csv', out / f'imagery_meta{sfx}.csv'

    df = pd.read_csv(args.roads_csv, usecols=['osm_id', 'wkt', 'lon', 'lat']).drop_duplicates('osm_id')
    if args.limit > 0:
        df = df.iloc[:args.limit]
    if args.shard:
        df = df[df['osm_id'] % sn == si]
    if args.tiles_only:
        failed = 0
        with ThreadPoolExecutor(args.workers) as ex:
            futs = {ex.submit(tiles_only, r): r.osm_id for r in df.itertuples()}
            for fut in tqdm(as_completed(futs), total=len(futs), mininterval=60):
                try:
                    fut.result()
                except Exception as e:
                    failed += 1
                    print('ERROR tiles', futs[fut], type(e).__name__, str(e)[:300], flush=True)
        print(f'tiles-only: {len(df)} roads, {failed} failed; {dict(sorted(STATS.items()))}', flush=True)
        sys.exit(1 if failed else 0)
    err_path = out / f'fetch_errors{sfx}.csv'
    cols = ['osm_id', 'zoom', 'n_windows', 'src_date', 'src_res', 'src_desc', 'nice_desc', 'nice_name']
    failed = {}
    for p in range(1, args.passes + 1):
        done = set()
        for f in out.glob('imagery_meta*.csv'):     # the merged file and every shard's
            try:     # another shard may be creating or appending to it right now
                done |= set(pd.to_numeric(pd.read_csv(f, usecols=['osm_id'], dtype=str, on_bad_lines='skip')['osm_id'],
                                          errors='coerce').dropna().astype('int64'))
            except (pd.errors.EmptyDataError, ValueError):
                pass
        todo = df[~df['osm_id'].isin(done)]
        print(f'pass {p}: {len(df)} roads, {len(done)} done, {len(todo)} to go', flush=True)
        if todo.empty:
            break
        if p > 1:
            time.sleep(120)     # let a rate limit cool down before retrying the failures
        failed = run_pass(todo, out, win_path, meta_path, err_path, cols, args.workers, p)
        print(f'pass {p}: {len(failed)} roads failed; http {dict(sorted(STATS.items()))}', flush=True)
    if failed:
        print(f'FAILED: {len(failed)} roads still have no imagery after {args.passes} passes, '
              f'see {err_path}. Rerun this command to try them again.', flush=True)
        sys.exit(1)
    print('ALL OK, errors: 0', flush=True)


def merge(out):
    """ fold shard files into windows.csv / imagery_meta.csv / fetch_errors.csv, dedup, drop the shard files """
    for base, key in (('windows', ['osm_id', 'k']), ('imagery_meta', ['osm_id']), ('fetch_errors', None)):
        parts = sorted(out.glob(f'{base}.*.csv'))
        if not parts:
            continue
        main = out / f'{base}.csv'
        dfs = [pd.read_csv(f, dtype=str) for f in [main, *parts] if f.exists() and f.stat().st_size > 0]
        df = pd.concat(dfs, ignore_index=True)
        if key:
            df = df.drop_duplicates(key, keep='last')
        tmp = out / f'{base}.merge.tmp'
        df.to_csv(tmp, index=False)
        tmp.replace(main)
        for f in parts:
            f.unlink()
        print(f'merged {base}: {len(parts)} shards, {len(df)} rows', flush=True)


def run_pass(todo, out, win_path, meta_path, err_path, cols, workers, p):
    new_win, new_meta, new_err = not win_path.exists(), not meta_path.exists(), not err_path.exists()
    failed, last = {}, time.time()
    with open(win_path, 'a') as fw, open(meta_path, 'a') as fm, open(err_path, 'a') as fe, \
            ThreadPoolExecutor(workers) as ex:
        if new_win:
            fw.write('osm_id,k,bearing_deg,gsd,path,zoom\n')
        if new_meta:
            fm.write(','.join(cols) + '\n')
        if new_err:
            fe.write('time,pass,osm_id,error\n')
        futs = {ex.submit(process, r, out / 'windows'): r.osm_id for r in todo.itertuples()}
        for fut in tqdm(as_completed(futs), total=len(futs), mininterval=60):
            if time.time() - last > 300:
                print(f'\nhttp so far: {dict(sorted(STATS.items()))}, failed this pass: {len(failed)}', flush=True)
                last = time.time()
            try:
                rows, meta = fut.result()
            except Exception as e:
                msg = f'{type(e).__name__}: {str(e)[:300]}'
                failed[futs[fut]] = msg
                fe.write(f'{time.strftime("%Y-%m-%dT%H:%M:%S")},{p},{futs[fut]},"{msg.replace(chr(34), chr(39))}"\n')
                fe.flush()
                print('ERROR', futs[fut], msg, flush=True)
                continue
            for r in rows:
                fw.write(f"{r['osm_id']},{r['k']},{r['bearing_deg']},{r['gsd']},{r['path']},{r['zoom']}\n")
            fm.write(','.join('"' + str(meta.get(c, '')).replace('"', "'") + '"' for c in cols) + '\n')
            fw.flush()
            fm.flush()
    return failed


if __name__ == '__main__':
    main()
