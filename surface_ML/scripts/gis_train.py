#!/usr/bin/env python3
""" Fine-tune GIScience's SUSformer (DINOv3 ViT-S/16 + gated-attention bag pooling) on
    NAIP, starting from their released road-surface weights.

    Uses their MILModel unchanged (layer-wise LR decay, frozen-backbone warm-up,
    OneCycle LR, label smoothing, class weights, EMA of weights). Data comes from
    gis_fetch.py windows; patches are cut on the fly with their placement jitter
    (+-1.5 m sideways, +-10 deg) and random bag subsets, plus flips and colour jitter in
    place of their albumentations pipeline.

    Usage: gis_train.py train_windows val_windows dataset_dir results_dir
                        [--patch-m 15] [--patch-px 128] [--epochs 8] [--freeze-epochs 1]
"""
import argparse
import math
import pathlib
import sys
from datetime import datetime, timezone

import numpy as np
import pandas as pd
import PIL.Image
import torch
from torch.utils.data import DataLoader, Dataset

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from paths import UPSTREAM_SUS     # noqa: E402
sys.path.insert(0, str(UPSTREAM_SUS / 'src'))
import lightning as L     # noqa: E402
from lightning.pytorch.callbacks import EarlyStopping, EMAWeightAveraging, ModelCheckpoint     # noqa: E402
from lightning.pytorch.loggers import CSVLogger     # noqa: E402
from road_surface_classifier.model import load_model     # noqa: E402

WEIGHTS = UPSTREAM_SUS / 'data/weights'


def cut_patch(win, gsd, bearing_deg, size_m, px, lateral_m=0.0):
    half = win.size[0] / 2
    t = math.radians(bearing_deg)
    ahead = np.array([math.cos(t), math.sin(t)]) * size_m / 2
    right = np.array([math.sin(t), -math.cos(t)]) * size_m / 2
    shift = np.array([math.sin(t), -math.cos(t)]) * lateral_m
    quad = []
    for c in (ahead - right, -ahead - right, -ahead + right, ahead + right):
        dx, dy = c + shift
        quad += [half + dx / gsd, half - dy / gsd]
    return win.transform((px, px), PIL.Image.QUAD, quad, PIL.Image.BILINEAR)


class BagDataset(Dataset):
    """ One item per road: a bag of patches. Label 0 = unpaved, 1 = paved (SUSformer order) """

    def __init__(self, windows_dir, dataset_csv, patch_m, patch_px, train):
        meta = pd.read_csv(pathlib.Path(windows_dir) / 'windows.csv')
        ds = pd.read_csv(dataset_csv)[['osm_id', 'class_num']]
        groups = dict(tuple(meta.groupby('osm_id')))
        self.items = [(groups[r.osm_id], 1 - int(r.class_num)) for r in ds.itertuples() if r.osm_id in groups]
        self.osm_ids = [int(g['osm_id'].iloc[0]) for g, _ in self.items]
        self.patch_m, self.patch_px, self.train = patch_m, patch_px, train

    def __len__(self):
        return len(self.items)

    def __getitem__(self, idx):
        g, label = self.items[idx]
        rng = np.random.default_rng() if self.train else None
        rows = list(g.itertuples())
        if self.train:
            rows = [rows[i] for i in sorted(rng.choice(len(rows), rng.integers(1, len(rows) + 1), replace=False))]
        flip_h = self.train and rng.random() < 0.5
        flip_v = self.train and rng.random() < 0.5
        gain = rng.uniform(0.85, 1.15, 3) if self.train else np.ones(3)
        patches = []
        for w in rows:
            win = PIL.Image.open(w.path).convert('RGB')
            if self.train:
                p = cut_patch(win, w.gsd, w.bearing_deg + rng.uniform(-10, 10), self.patch_m, self.patch_px,
                              lateral_m=rng.uniform(-1.5, 1.5))
            else:
                p = cut_patch(win, w.gsd, w.bearing_deg, self.patch_m, self.patch_px)
            a = np.asarray(p).astype(np.float32) / 255.0
            if ((a <= 1 / 255).all(-1) | (a >= 254 / 255).all(-1)).mean() > 0.1 and len(rows) > 1:
                continue
            a = np.clip(a * gain, 0, 1).astype(np.float32)
            if flip_h:
                a = a[:, ::-1]
            if flip_v:
                a = a[::-1]
            patches.append(torch.from_numpy(a.copy()).permute(2, 0, 1))
        if not patches:     # every patch was fill: keep a blank one so the batch still forms
            patches = [torch.zeros(3, self.patch_px, self.patch_px)]
        return torch.stack(patches), torch.tensor(label)


def collate(bags):
    images, labels = zip(*bags)
    return torch.cat(images), [len(b) for b in images], torch.stack(labels)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('train_windows')
    ap.add_argument('val_windows')
    ap.add_argument('dataset_dir')
    ap.add_argument('results_dir')
    ap.add_argument('--patch-m', type=float, default=15.0)
    ap.add_argument('--patch-px', type=int, default=128)
    ap.add_argument('--epochs', type=int, default=8)
    ap.add_argument('--freeze-epochs', type=int, default=1)
    ap.add_argument('--lr', type=float, default=5e-5)
    ap.add_argument('--batch-size', type=int, default=16)
    ap.add_argument('--workers', type=int, default=3)
    ap.add_argument('--threads', type=int, default=6)
    ap.add_argument('--patience', type=int, default=3)
    ap.add_argument('--limit', type=int, default=-1)
    ap.add_argument('--init-ckpt', help='start from a fine-tuned checkpoint (e.g. the NAIP one) instead of the release')
    args = ap.parse_args()
    torch.set_num_threads(args.threads)

    ds_dir = pathlib.Path(args.dataset_dir)
    train_ds = BagDataset(args.train_windows, ds_dir / 'dataset_train.csv', args.patch_m, args.patch_px, True)
    val_ds = BagDataset(args.val_windows, ds_dir / 'dataset_val.csv', args.patch_m, args.patch_px, False)
    if args.limit > 0:
        train_ds.items = train_ds.items[:args.limit]
        val_ds.items, val_ds.osm_ids = val_ds.items[:args.limit // 4], val_ds.osm_ids[:args.limit // 4]
    labels = np.array([lab for _, lab in train_ds.items])
    class_weights = [float(len(labels) / (2 * (labels == c).sum())) for c in (0, 1)]
    print(f'train {len(train_ds)} roads, val {len(val_ds)}, class weights {class_weights}')

    model = load_model(WEIGHTS / 'head.pt', WEIGHTS / 'enc/encoder.pt', class_weights=class_weights,
                       lr=args.lr, freeze_epochs=args.freeze_epochs, trainable='all')
    if args.init_ckpt:
        sd = torch.load(args.init_ckpt, map_location='cpu', weights_only=False)['state_dict']
        missing, unexpected = model.load_state_dict(sd, strict=False)
        print(f'init from {args.init_ckpt}: {len(missing)} missing, {len(unexpected)} unexpected keys')
    save_dir = pathlib.Path(args.results_dir) / datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%SZ')
    save_dir.mkdir(parents=True)
    kw = dict(collate_fn=collate, num_workers=args.workers, persistent_workers=True)
    train_dl = DataLoader(train_ds, batch_size=args.batch_size, shuffle=True, **kw)
    val_dl = DataLoader(val_ds, batch_size=32, **kw)
    ckpt = ModelCheckpoint(dirpath=save_dir, monitor='val_acc', mode='max', save_top_k=3, save_last=True,
                           filename='sus-{epoch:02d}-{val_acc:.5f}')
    trainer = L.Trainer(accelerator='cpu', max_epochs=args.epochs, log_every_n_steps=20,
                        callbacks=[ckpt, EarlyStopping(monitor='val_acc', mode='max', patience=args.patience),
                                   EMAWeightAveraging(decay=0.995)],
                        logger=CSVLogger(str(save_dir), name='logs'))
    trainer.fit(model, train_dl, val_dl)
    print('Best checkpoint:', ckpt.best_model_path)


if __name__ == '__main__':
    main()
