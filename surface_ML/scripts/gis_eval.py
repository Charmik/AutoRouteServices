#!/usr/bin/env python3
""" Per-road paved/unpaved probabilities from a fine-tuned SUSformer checkpoint
    (gis_train.py) on a split, optionally averaged over horizontal/vertical flips.

    Output matches gis_infer.py: osm_id, y_true (1 = unpaved, as in our datasets),
    p_unpaved, n_patches.

    Usage: gis_eval.py ckpt windows_dir dataset.csv out.csv [--patch-m 15] [--patch-px 128] [--tta] [--int8]
      --int8: dynamic int8 quantization of the Linear layers (CPU speed-up)
"""
import argparse
import pathlib
import sys

import numpy as np
import pandas as pd
import torch
from torch.utils.data import DataLoader

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gis_train import BagDataset, collate     # noqa: E402  (also puts giscience/src on sys.path)
from road_surface_classifier.model import MILModel     # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('ckpt')
ap.add_argument('windows_dir')
ap.add_argument('dataset_csv')
ap.add_argument('out_csv')
ap.add_argument('--patch-m', type=float, default=15.0)
ap.add_argument('--patch-px', type=int, default=128)
ap.add_argument('--tta', action='store_true')
ap.add_argument('--threads', type=int, default=6)
ap.add_argument('--int8', action='store_true')
ap.add_argument('--workers', type=int, default=2)
args = ap.parse_args()
torch.set_num_threads(args.threads)

ds = BagDataset(args.windows_dir, args.dataset_csv, args.patch_m, args.patch_px, train=False)
dl = DataLoader(ds, batch_size=32, collate_fn=collate, num_workers=args.workers)
model = MILModel.load_from_checkpoint(args.ckpt, map_location='cpu', pretrained=False).eval()
if args.int8:
    model = torch.ao.quantization.quantize_dynamic(model, {torch.nn.Linear}, dtype=torch.qint8)
flips = [[], [-1], [-2], [-1, -2]] if args.tta else [[]]
probs, ys, ns = [], [], []
with torch.no_grad():
    for images, sizes, labels in dl:
        p = 0
        for f in flips:
            logits, _ = model(images.flip(f) if f else images, sizes)
            p = p + logits.softmax(1)
        probs.append((p / len(flips))[:, 0].numpy())
        ys.append(1 - labels.numpy())
        ns += sizes
out = pd.DataFrame(dict(osm_id=ds.osm_ids, y_true=np.concatenate(ys), p_unpaved=np.concatenate(probs), n_patches=ns))
out.to_csv(args.out_csv, index=False)
acc = ((out['p_unpaved'] > 0.5).astype(int) == out['y_true']).mean()
print(f'{args.ckpt}\ntta={args.tta}: {len(out)} roads, paved/unpaved accuracy {acc:.4f}')
