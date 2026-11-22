#!/usr/bin/env python3
""" Contact sheet of the most confident errors (RGB chip, OSM way in red)

    Usage: error_sheet.py val_probs.csv out.png [--n 24] [--prob-col p_unpaved]
"""
import argparse

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt     # noqa: E402
import numpy as np     # noqa: E402
import pandas as pd     # noqa: E402
import PIL.Image     # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument('csv')
ap.add_argument('out')
ap.add_argument('--n', type=int, default=24)
ap.add_argument('--prob-col', default='p_unpaved')
args = ap.parse_args()

df = pd.read_csv(args.csv, low_memory=False)
p = df[args.prob_col]
df['wrong_conf'] = np.where((p > 0.5) != (df['y_true'] == 1), np.abs(p - 0.5), -1)
err = df[df['wrong_conf'] >= 0].sort_values('wrong_conf', ascending=False).head(args.n)
cols = 6
rows = int(np.ceil(len(err) / cols))
fig, axs = plt.subplots(rows, cols, figsize=(cols * 3, rows * 3.3))
for ax, r in zip(axs.flat, err.itertuples()):
    im = np.array(PIL.Image.open(r.chip_path))[..., :3].copy()
    mask = np.array(PIL.Image.open(r.mask_path)) > 0
    im[mask] = (0.5 * im[mask] + [127, 0, 0]).astype(np.uint8)
    ax.imshow(im)
    ax.set_title(f'{r.osm_id}\nOSM {r.osm_surface} / pred {"unpaved" if getattr(r, args.prob_col) > 0.5 else "paved"} '
                 f'{max(getattr(r, args.prob_col), 1 - getattr(r, args.prob_col)):.2f}', fontsize=7)
for ax in axs.flat:
    ax.axis('off')
plt.tight_layout()
plt.savefig(args.out, dpi=80)
