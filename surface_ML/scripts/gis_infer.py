#!/usr/bin/env python3
""" Run the GIScience SUSformer ONNX model (pretrained, as released) on the windows
    from gis_fetch.py: cut each patch with the road running up it, as SUSformer's
    materialize.py does, and score each road's patches as one bag.

    Usage: gis_infer.py windows_dir dataset.csv out.csv [--patch-m 15] [--threads N]
                        [--onnx path] [--save-examples N]
"""
import argparse
import math
import pathlib

import numpy as np
import onnxruntime as ort
import pandas as pd
import PIL.Image
from tqdm import tqdm

from paths import UPSTREAM_SUS

PATCH_PX = 256
ONNX = UPSTREAM_SUS / 'data/weights/dinov3s_road_surface.onnx'


def cut_patch(win: PIL.Image.Image, gsd: float, bearing_deg: float, size_m: float) -> PIL.Image.Image:
    """ Square patch of size_m centred in a north-up window, road running up the patch """
    half = win.size[0] / 2
    t = math.radians(bearing_deg)
    ahead = np.array([math.cos(t), math.sin(t)]) * size_m / 2
    right = np.array([math.sin(t), -math.cos(t)]) * size_m / 2
    corners = [ahead - right, -ahead - right, -ahead + right, ahead + right]     # TL, BL, BR, TR
    quad = []
    for dx, dy in corners:
        quad += [half + dx / gsd, half - dy / gsd]
    return win.transform((PATCH_PX, PATCH_PX), PIL.Image.QUAD, quad, PIL.Image.BILINEAR)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('windows_dir')
    ap.add_argument('dataset_csv')
    ap.add_argument('out_csv')
    ap.add_argument('--patch-m', type=float, default=15.0)
    ap.add_argument('--threads', type=int, default=6)
    ap.add_argument('--onnx', default=str(ONNX))
    ap.add_argument('--save-examples', type=int, default=0)
    args = ap.parse_args()

    opts = ort.SessionOptions()
    opts.intra_op_num_threads = args.threads
    sess = ort.InferenceSession(args.onnx, opts)
    wdir = pathlib.Path(args.windows_dir)
    meta = pd.read_csv(wdir / 'windows.csv')
    ds = pd.read_csv(args.dataset_csv)[['osm_id', 'class_num']]
    groups = dict(tuple(meta.groupby('osm_id')))
    rows = []
    for i, r in enumerate(tqdm(ds.itertuples(), total=len(ds), mininterval=60)):
        g = groups.get(r.osm_id)
        if g is None:
            continue
        patches = []
        for w in g.itertuples():
            win = PIL.Image.open(w.path).convert('RGB')
            p = cut_patch(win, w.gsd, w.bearing_deg, args.patch_m)
            a = np.asarray(p)
            # SUSformer drops patches that are mostly fill (off the image)
            if ((a <= 1).all(-1) | (a >= 254).all(-1)).mean() > 0.1:
                continue
            patches.append(a)
            if i < args.save_examples:
                p.save(pathlib.Path(args.out_csv).with_suffix('') .as_posix() + f'_ex_{r.osm_id}_{w.k}.png')
        if not patches:
            continue
        x = np.stack(patches).astype(np.float32).transpose(0, 3, 1, 2) / 255.0
        logits = sess.run(None, {'image': x})[0][0]
        e = np.exp(logits - logits.max())
        p_unpaved = float(e[0] / e.sum())     # SUSformer class order: unpaved, paved
        rows.append((r.osm_id, r.class_num, p_unpaved, len(patches)))
    out = pd.DataFrame(rows, columns=['osm_id', 'y_true', 'p_unpaved', 'n_patches'])
    out.to_csv(args.out_csv, index=False)
    acc = ((out['p_unpaved'] > 0.5).astype(int) == out['y_true']).mean()
    print(f'patch {args.patch_m} m: {len(out)} of {len(ds)} roads scored, paved/unpaved accuracy {acc:.4f}')


if __name__ == '__main__':
    main()
