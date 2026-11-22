#!/usr/bin/env python3
""" Accuracy of a checkpoint (or an ensemble of them) on a dataset split:
    all classes and paved/unpaved.

    --tta averages class probabilities over the 4 horizontal/vertical flips.

    Usage: eval_ckpt.py ckpt [ckpt ...] dataset_dir [--split val] [--limit N] [--tta]
"""
import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from paths import UPSTREAM_MASKCNN     # noqa: E402
sys.path.insert(0, str(UPSTREAM_MASKCNN))

import numpy as np     # noqa: E402
import pandas as pd     # noqa: E402
import torch     # noqa: E402
from torch.utils.data import DataLoader     # noqa: E402

from rsc.train.plmcnn import PLMaskCNN     # noqa: E402
from rsc.train.preprocess import PreProcess     # noqa: E402
from rsc.train.dataset import RoadSurfaceDataset     # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('ckpt', nargs='+')
ap.add_argument('dataset_dir')
ap.add_argument('--split', default='val')
ap.add_argument('--limit', type=int, default=-1)
ap.add_argument('--threads', type=int, default=2)
ap.add_argument('--tta', action='store_true')
ap.add_argument('--out', help='CSV of per-chip class probabilities')
args = ap.parse_args()
torch.set_num_threads(args.threads)

ds_dir = pathlib.Path(args.dataset_dir)
w = pd.read_csv(ds_dir / 'class_weights.csv')
labels, top = list(w['class_name']), np.array(w['top_level'])
n = len(labels)
ds = RoadSurfaceDataset(str(ds_dir / f'dataset_{args.split}.csv'), transform=PreProcess(),
                        chip_size=224, limit=args.limit, n_channels=4)
ds.n_classes = n
dl = DataLoader(ds, batch_size=32, num_workers=1)

models = [PLMaskCNN.load_from_checkpoint(c, map_location='cpu').eval() for c in args.ckpt]
# A finer-grained model (e.g. 8 surfaces) can score a paved/unpaved dataset: its class
# probabilities are summed per top-level class
for m in models:
    if list(m.labels) == labels:
        m.to_ds = None
    else:
        assert labels == ['paved', 'unpaved'], 'checkpoints must match the dataset classes'
        m.to_ds = torch.nn.functional.one_hot(torch.as_tensor(m.top_level_map), 2).float()
flips = [[], [-1], [-2], [-1, -2]] if args.tta else [[]]
yt, yp, pr = [], [], []
with torch.no_grad():
    for x, z in dl:
        p = 0
        for m in models:
            xi = x[:, :m.nc + 1]
            for f in flips:
                _, z_hat = m(xi.flip(f) if f else xi)
                if m.to_ds is None:
                    p = p + z_hat[:, :n].softmax(1)
                else:
                    p = p + z_hat[:, :len(m.labels)].softmax(1) @ m.to_ds
        p = p / (len(models) * len(flips))
        pr.append(p.numpy())
        yp.append(p.argmax(1).numpy())
        yt.append(z[:, :n].argmax(1).numpy())
yt, yp, pr = np.concatenate(yt), np.concatenate(yp), np.concatenate(pr)

print('\n'.join(args.ckpt) + f'\ntta={args.tta}  n={len(yt)}')
print(f'all-class accuracy:     {(yt == yp).mean():.3f}')
print(f'paved/unpaved accuracy: {(top[yt] == top[yp]).mean():.3f}')
for t, name in ((0, 'paved'), (1, 'unpaved')):
    m = top[yt] == t
    print(f'  {name:8s} recall {(top[yp][m] == t).mean():.3f}  (n={m.sum()})')
print('per-class recall:')
for c in range(n):
    m = yt == c
    print(f'  {labels[c]:14s} {(yp[m] == c).mean():.3f}  (n={m.sum()})')

meta = pd.read_csv(ds_dir / f'dataset_{args.split}.csv').iloc[:len(yt)]
if 'source' in meta:
    ok = top[yt] == top[yp]
    print('paved/unpaved accuracy by sample source:')
    for src, m in meta.groupby('source').groups.items():
        print(f'  {src:8s} {ok[m].mean():.3f}  (n={len(m)})')
    print('by OSM surface tag (n >= 20):')
    g = pd.Series(ok).groupby(meta['osm_surface'].values)
    for tag, acc in g.mean().sort_values().items():
        if g.size()[tag] >= 20:
            print(f'  {tag:16s} {acc:.3f}  (n={g.size()[tag]})')

if args.out:
    out = meta.copy()
    out['y_true'], out['y_pred'] = yt, yp
    for c in range(n):
        out[f'p_{labels[c]}'] = pr[:, c]
    out.to_csv(args.out, index=False)
    print('wrote', args.out)
