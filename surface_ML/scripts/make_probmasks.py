#!/usr/bin/env python3
""" Generate "probmasks" (pseudo-truth road segmentation) as in notebook 04,
    but without the author's ~1000 hand-labeled obscuration chips.

    Notebook 04 fit a logistic regression on (NIR, L, a, b) colors:
      positives = geometric-median road color of chips labeled unobscured
      negatives = random pixels from chips labeled fully obscured
    Here those chip labels come from NDVI measured under the OSM way instead:
      unobscured ~ low NDVI under the way, fully obscured ~ high NDVI under the way.
    Everything after the classifier (blur, canny width estimate, distance PDF)
    is copied from notebook 04.

    Usage: make_probmasks.py features.csv data_dir [--fit-samples N] [--workers N]
"""
import argparse
import pathlib
import pickle
import sys
from multiprocessing import Pool

import numpy as np
import pandas as pd
import PIL.Image
import scipy.ndimage
import skimage.color
import skimage.feature
import skimage.morphology
from osgeo import gdal, osr
from scipy.stats import norm
from sklearn.linear_model import LogisticRegressionCV
from tqdm import tqdm

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from paths import UPSTREAM_MASKCNN     # noqa: E402
sys.path.insert(0, str(UPSTREAM_MASKCNN))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from rsc.common.geometric_median import geometric_median     # noqa: E402
from fetch_chips import draw_mask     # noqa: E402

gdal.UseExceptions()

DATA: pathlib.Path
CLF = None


def pdf_y(x, sigma):
    return norm.pdf(x, scale=sigma) * np.sqrt(2 * np.pi * sigma**2)


def load(osm_id):
    im = gdal.Open(str(DATA / 'imagery' / f'{osm_id}.tif')).ReadAsArray().transpose(1, 2, 0)
    mask = np.array(PIL.Image.open(DATA / 'masks' / f'{osm_id}.png'))
    return im, mask


def irlab(px: np.ndarray) -> np.ndarray:
    """ (N, 4) RGBN uint8 -> (N, 4) NIR, L, a, b (notebook 04 latent space) """
    return np.hstack((px[:, (3,)] * (100.0 / 255),
                      skimage.color.rgb2lab(px[:, :3].reshape(-1, 1, 3)).reshape(-1, 3)))


def ndvi_under_way(osm_id):
    im, mask = load(osm_id)
    px = im[mask > 0].astype(float)
    if len(px) < 10:
        return osm_id, np.nan
    nir, red = px[:, 3], px[:, 0]
    return osm_id, float(np.median((nir - red) / (nir + red + 1e-6)))


def pos_sample(osm_id):
    im, mask = load(osm_id)
    return geometric_median(irlab(im[mask > 0]))


def neg_samples(args):
    osm_id, n = args
    im, _ = load(osm_id)
    # Unlike the hand-labeled originals, an NDVI-selected "obscured" chip can still
    # contain visible pavement or dark shadows: sample vegetation pixels only
    px = im.reshape(-1, 4).astype(float)
    veg = np.where((px[:, 3] - px[:, 0]) / (px[:, 3] + px[:, 0] + 1e-6) > 0.2)[0]
    if len(veg) == 0:
        return np.empty((0, 4))
    rng = np.random.default_rng(osm_id)
    return irlab(im.reshape(-1, 4)[rng.choice(veg, n)])


def chip_srs(osm_id):
    srs = osr.SpatialReference()
    srs.ImportFromWkt(gdal.Open(str(DATA / 'imagery' / f'{osm_id}.tif')).GetProjection())
    srs.SetAxisMappingStrategy(osr.OAMS_TRADITIONAL_GIS_ORDER)
    return srs


def make_probmask(row):
    """ Notebook 04, final cell """
    osm_id, wkt = row
    out_file = DATA / 'probmasks' / f'{osm_id}.png'
    if out_file.exists():
        return
    im, mask = load(osm_id)
    pred = CLF.predict_proba(irlab(im.reshape(-1, 4)))[:, 0]
    pred = pred.reshape(im.shape[:2])
    pred_clf = scipy.ndimage.gaussian_filter(pred, sigma=1)

    # Canny edges + distance transform to estimate road width
    edges = skimage.feature.canny(pred_clf, sigma=2)
    edges = ~skimage.morphology.area_closing(~edges, 50, connectivity=2)
    dist = scipy.ndimage.distance_transform_edt(~edges)
    # < 2 lanes or > 6 lanes, assuming 10 ft lanes: fall back to 2 lanes
    w = 2 * np.median(dist[np.where(mask)]).astype(int)
    if w < 3 or w > 23:
        w = 6

    # Redraw the way mask at the estimated width
    tmp = DATA / 'probmasks' / f'{osm_id}.wide.png'
    draw_mask(wkt, DATA / 'imagery' / f'{osm_id}.tif', chip_srs(osm_id), tmp, width=int(w))
    wide = np.array(PIL.Image.open(tmp)) > 0
    tmp.unlink()

    dist_m = scipy.ndimage.distance_transform_edt(~wide)
    pred = (pred_clf * pdf_y(dist_m, w / 3.0) * 255.0).astype(np.uint8)
    PIL.Image.fromarray(pred).save(out_file, format='PNG')


def init_worker(clf, data):
    global CLF, DATA
    CLF, DATA = clf, data


def main():
    global DATA
    ap = argparse.ArgumentParser()
    ap.add_argument('features_csv')
    ap.add_argument('data_dir')
    ap.add_argument('--fit-samples', type=int, default=4000)
    ap.add_argument('--workers', type=int, default=6)
    args = ap.parse_args()
    DATA = pathlib.Path(args.data_dir)
    (DATA / 'probmasks').mkdir(exist_ok=True)

    log = pd.read_csv(DATA / 'fetch_log.csv')
    ok = set(log.loc[log['status'] == 'ok', 'osm_id'])
    df = pd.read_csv(args.features_csv)
    df = df[df['osm_id'].isin(ok)]
    print(f'{len(df)} chips')

    clf_path = DATA / 'road_color_clf.pkl'
    if clf_path.exists():
        clf = pickle.loads(clf_path.read_bytes())
    else:
        # 1. Weak obscuration labels from NDVI under the way
        fit_ids = df['osm_id'].sample(min(args.fit_samples, len(df)), random_state=0).tolist()
        with Pool(args.workers, initializer=init_worker, initargs=(None, DATA)) as pool:
            ndvi = dict(tqdm(pool.imap_unordered(ndvi_under_way, fit_ids, chunksize=16),
                             total=len(fit_ids), desc='ndvi'))
        s = pd.Series(ndvi).dropna()
        lo, hi = s.quantile(0.35), s.quantile(0.90)
        pos_ids = s[s <= min(lo, 0.10)].index.tolist()
        neg_ids = s[s >= max(hi, 0.30)].index.tolist()
        print(f'NDVI under way: median {s.median():.3f}; '
              f'{len(pos_ids)} "unobscured" chips (<= {min(lo, 0.10):.3f}), '
              f'{len(neg_ids)} "obscured" chips (>= {max(hi, 0.30):.3f})')

        # 2. Color samples, as in notebook 04
        with Pool(args.workers, initializer=init_worker, initargs=(None, DATA)) as pool:
            pos = np.array(list(tqdm(pool.imap(pos_sample, pos_ids, chunksize=16),
                                     total=len(pos_ids), desc='pos')))
            n_per = max(1, len(pos_ids) // max(1, len(neg_ids)))
            neg = np.vstack(list(tqdm(pool.imap(neg_samples, [(i, n_per) for i in neg_ids],
                                                chunksize=16), total=len(neg_ids), desc='neg')))
        X = np.vstack((pos, neg))
        y = np.concatenate(([0] * len(pos), [1] * len(neg)))
        clf = LogisticRegressionCV(max_iter=1000, l1_ratios=(0,), use_legacy_attributes=False).fit(X, y)
        print(f'Road color classifier train accuracy: {clf.score(X, y):.3f} '
              f'({len(pos)} pos / {len(neg)} neg)')
        clf_path.write_bytes(pickle.dumps(clf))

    # 3. Probmask for every chip
    rows = list(zip(df['osm_id'], df['wkt']))
    with Pool(args.workers, initializer=init_worker, initargs=(clf, DATA)) as pool:
        for _ in tqdm(pool.imap_unordered(make_probmask, rows, chunksize=16), total=len(rows),
                      desc='probmasks', mininterval=10):
            pass


if __name__ == '__main__':
    main()
