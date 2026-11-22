#!/usr/bin/env python3
""" Build dataset_{full,train,val}.csv and class_weights.csv (notebook 02, last step).

    Differences from the notebook:
      - adds the 'top_level' column scripts/train.py expects (0 = paved, 1 = unpaved)
      - train/val split by ~0.1 degree grid cell instead of per way, so adjacent
        segments of the same road can't sit on both sides of the split

    With --binary, classes come from the features' 'binary' column (paved / unpaved)
    and the 'source' / 'osm_surface' columns are carried through for evaluation.

    --keep-split DIR keeps the grid cells of an earlier dataset on the same side
    (needed when warm starting from a model trained on that dataset's train split);
    only cells new to this dataset are drawn at random.

    Usage: make_dataset.py features.csv data_dir out_dir [--val-pc 20] [--binary]
                           [--keep-split DIR]
"""
import argparse
import pathlib

import numpy as np
import pandas as pd

CLASSES = ['asphalt', 'bricks', 'concrete', 'paving_stones',
           'compacted', 'dirt', 'gravel', 'ground']
TOP_LEVEL = {'asphalt': 0, 'bricks': 0, 'concrete': 0, 'paving_stones': 0,
             'compacted': 1, 'dirt': 1, 'gravel': 1, 'ground': 1}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('features_csv')
    ap.add_argument('data_dir')
    ap.add_argument('out_dir')
    ap.add_argument('--val-pc', type=float, default=20)
    ap.add_argument('--binary', action='store_true')
    ap.add_argument('--keep-split')
    args = ap.parse_args()
    global CLASSES, TOP_LEVEL
    data = pathlib.Path(args.data_dir).resolve()
    out = pathlib.Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    df = pd.read_csv(args.features_csv)
    if args.binary:
        CLASSES, TOP_LEVEL = ['paved', 'unpaved'], {'paved': 0, 'unpaved': 1}
        df['surface'] = df['binary']
    df['chip_path'] = [str(data / 'imagery' / f'{i}.tif') for i in df['osm_id']]
    df['mask_path'] = [str(data / 'masks' / f'{i}.png') for i in df['osm_id']]
    df['probmask_path'] = [str(data / 'probmasks' / f'{i}.png') for i in df['osm_id']]
    have = [all(pathlib.Path(p).exists() for p in ps)
            for ps in zip(df['chip_path'], df['mask_path'], df['probmask_path'])]
    print(f'{sum(have)} of {len(df)} features have chip + mask + probmask')
    df = df[have]

    # Drop classes that ended up empty, keep notebook class order
    classes = [c for c in CLASSES if (df['surface'] == c).any()]
    class_num = {c: i for i, c in enumerate(classes)}
    df_full = pd.DataFrame(dict(osm_id=df['osm_id'],
                                class_num=[class_num[s] for s in df['surface']],
                                chip_path=df['chip_path'],
                                mask_path=df['mask_path'],
                                probmask_path=df['probmask_path'],
                                lon=df['lon'], lat=df['lat'])).set_index('osm_id')
    if args.binary:
        df_full['source'] = df['source'].values
        df_full['osm_surface'] = df['osm_surface'].values

    # Spatial split by grid cell
    cell = (np.floor(df_full['lon'] * 10).astype(int).astype(str) + '_' +
            np.floor(df_full['lat'] * 10).astype(int).astype(str))
    cells = cell.unique()
    rng = np.random.default_rng(42)
    val_cells, train_cells = set(), set()
    if args.keep_split:
        def cells_of(split):
            d = pd.read_csv(pathlib.Path(args.keep_split) / f'dataset_{split}.csv')
            return set(np.floor(d['lon'] * 10).astype(int).astype(str) + '_' +
                       np.floor(d['lat'] * 10).astype(int).astype(str))
        val_cells, train_cells = cells_of('val'), cells_of('train')
        assert not val_cells & train_cells
    free = np.array([c for c in cells if c not in val_cells | train_cells])
    val_cells |= set(rng.choice(free, int(len(free) * args.val_pc / 100), replace=False))
    is_val = cell.isin(val_cells)
    df_train, df_val = df_full[~is_val], df_full[is_val]

    totals = [int((df_full['class_num'] == n).sum()) for n in range(len(classes))]
    df_class = pd.DataFrame(dict(
        class_num=range(len(classes)),
        class_name=classes,
        top_level=[TOP_LEVEL[c] for c in classes],
        total_train=[int((df_train['class_num'] == n).sum()) for n in range(len(classes))],
        total_val=[int((df_val['class_num'] == n).sum()) for n in range(len(classes))],
        total=totals,
        weight=[(len(df_full) / len(classes)) / t for t in totals])).set_index('class_num')

    df_full.to_csv(out / 'dataset_full.csv')
    df_train.to_csv(out / 'dataset_train.csv')
    df_val.to_csv(out / 'dataset_val.csv')
    df_class.to_csv(out / 'class_weights.csv')
    print(df_class.to_string())
    print(f'train {len(df_train)}  val {len(df_val)}')


if __name__ == '__main__':
    main()
