#!/usr/bin/env python3
""" scripts/train.py adapted to run here: CPU, local paths, CSV logging instead of
    the author's MLflow server. Model, loss, hyperparameters and callbacks unchanged.

    Additions for the paved/unpaved run (all opt-in):
      --init ckpt       warm start from another run's checkpoint; a classifier head with a
                        different class count is rebuilt from the old head (rows averaged
                        per top-level class, obscuration row copied)
      --monitor val_acc checkpoint / early-stop on top-level (paved/unpaved) val accuracy
      --plateau         reduce LR x0.3 when the monitored metric stalls for an epoch

    Usage: train_cpu.py dataset_dir results_dir [--max-epochs N] [--quick-test]
"""
import argparse
import pathlib
import sys
from datetime import datetime, timezone

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from paths import UPSTREAM_MASKCNN     # noqa: E402
sys.path.insert(0, str(UPSTREAM_MASKCNN))

import pandas as pd     # noqa: E402
import torch     # noqa: E402
from torch.utils.data import DataLoader     # noqa: E402
import pytorch_lightning as pl     # noqa: E402
from pytorch_lightning.callbacks import (ModelCheckpoint, EarlyStopping,     # noqa: E402
                                         StochasticWeightAveraging)
from pytorch_lightning.loggers import CSVLogger     # noqa: E402

from rsc.train.plmcnn import PLMaskCNN     # noqa: E402
from rsc.train.preprocess import PreProcess     # noqa: E402
from rsc.train.dataset import RoadSurfaceDataset     # noqa: E402

INCLUDE_NIR = True


class PLMaskCNNAcc(PLMaskCNN):
    """ PLMaskCNN that also logs top-level (paved/unpaved) val accuracy """

    plateau_monitor = None

    def validation_step(self, batch, batch_idx):
        x, z = batch
        y = x[:, self.nc + 1:self.nc + 2, :, :]
        x = x[:, 0:self.nc + 1, :, :]
        y_hat, z_hat = self.forward(x)
        loss = self.loss(y_hat, y, z_hat, z)
        top = torch.as_tensor(self.top_level_map, device=z.device)
        n = len(self.labels)
        acc = (top[z_hat[:, :n].argmax(1)] == top[z[:, :n].argmax(1)]).float().mean()
        self.log_dict({'val_loss_im': self.loss.seg_loss, 'val_loss_cl': self.loss.cl_loss,
                       'val_loss_ob': self.loss.ob_loss, 'val_loss': loss, 'val_acc': acc},
                      on_step=False, on_epoch=True)
        return loss

    def configure_optimizers(self):
        opt = torch.optim.Adam(self.parameters(), lr=self._lr)
        if self.plateau_monitor is None:
            return opt
        mode = 'max' if self.plateau_monitor == 'val_acc' else 'min'
        sched = torch.optim.lr_scheduler.ReduceLROnPlateau(opt, mode=mode, factor=0.3, patience=1)
        return {'optimizer': opt,
                'lr_scheduler': {'scheduler': sched, 'monitor': self.plateau_monitor}}


def warm_start(model, ckpt_path, top_level_map):
    ck = torch.load(ckpt_path, map_location='cpu', weights_only=False)
    sd = ck['state_dict']
    old_top = ck['hyper_parameters']['top_level_map']
    w, b = sd['model.fc.weight'], sd['model.fc.bias']
    if w.shape[0] != len(top_level_map) + 1:
        # Old head: one row per old class + obscuration. New head: one row per new class,
        # each the mean of the old rows under the same top-level class
        rows = [[i for i, t in enumerate(old_top) if t == nt] for nt in top_level_map]
        sd['model.fc.weight'] = torch.stack([w[r].mean(0) for r in rows] + [w[-1]])
        sd['model.fc.bias'] = torch.stack([b[r].mean(0) for r in rows] + [b[-1]])
    print('warm start:', model.load_state_dict(sd, strict=True))

if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('dataset_dir')
    ap.add_argument('results_dir')
    ap.add_argument('--max-epochs', type=int, default=1000)
    ap.add_argument('--patience', type=int, default=10)
    ap.add_argument('--batch-size', type=int, default=64)
    ap.add_argument('--workers', type=int, default=3)
    ap.add_argument('--threads', type=int, default=6)
    ap.add_argument('--quick-test', action='store_true')
    ap.add_argument('--resume', help='checkpoint (e.g. results/<run>/last.ckpt) to resume from')
    ap.add_argument('--init', help='checkpoint to warm start from')
    ap.add_argument('--monitor', default='val_loss', choices=('val_loss', 'val_acc'))
    ap.add_argument('--plateau', action='store_true')
    ap.add_argument('--swa', action='store_true',
                    help='author\'s SWA callback; it starts at 80%% of max_epochs, which their '
                         'runs (max_epochs=1000 + early stopping) never reached')
    args = ap.parse_args()
    torch.set_num_threads(args.threads)

    ds_dir = pathlib.Path(args.dataset_dir)
    now = datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%SZ')
    save_dir = pathlib.Path(args.results_dir) / now
    save_dir.mkdir(parents=True, exist_ok=False)

    weights_df = pd.read_csv(ds_dir / 'class_weights.csv')
    labels = list(weights_df['class_name'])
    top_level_map = list(weights_df['top_level'])
    class_weights = list(weights_df['weight'])

    limit = 500 if args.quick_test else -1
    preprocess = PreProcess()
    nc = 4 if INCLUDE_NIR else 3
    train_ds = RoadSurfaceDataset(str(ds_dir / 'dataset_train.csv'), transform=preprocess,
                                  chip_size=224, limit=limit, n_channels=nc)
    val_ds = RoadSurfaceDataset(str(ds_dir / 'dataset_val.csv'), transform=preprocess,
                                chip_size=224, limit=limit, n_channels=nc)
    # The dataset infers class count from the max class_num in its own split; a split
    # missing the last class would then get short label vectors
    train_ds.n_classes = val_ds.n_classes = len(labels)
    train_dl = DataLoader(train_ds, num_workers=args.workers, batch_size=args.batch_size,
                          shuffle=True, persistent_workers=True)
    val_dl = DataLoader(val_ds, num_workers=args.workers, batch_size=args.batch_size,
                        persistent_workers=True)

    learning_rate = 0.00040984645874638675
    model = PLMaskCNNAcc(weights=class_weights, labels=labels, nc=nc,
                      top_level_map=top_level_map, learning_rate=learning_rate,
                      seg_k=0.7, ob_k=0.9)
    if args.init:
        warm_start(model, args.init, top_level_map)
    if args.plateau:
        model.plateau_monitor = args.monitor
    torch.save(model, save_dir / 'model.pth')
    model.set_stage(0, learning_rate)

    mode = 'max' if args.monitor == 'val_acc' else 'min'
    checkpoint_callback = ModelCheckpoint(dirpath=str(save_dir), monitor=args.monitor, mode=mode,
                                          save_top_k=3, save_last=True,
                                          filename='model-0-{epoch:02d}-{%s:.5f}' % args.monitor)
    early_stopping_callback = EarlyStopping(monitor=args.monitor, mode=mode,
                                            patience=args.patience)
    callbacks = [checkpoint_callback, early_stopping_callback]
    if args.swa:
        callbacks.append(StochasticWeightAveraging(swa_lrs=0.6863423660749621))
    trainer = pl.Trainer(accelerator='cpu',
                         max_epochs=1 if args.quick_test else args.max_epochs,
                         callbacks=callbacks,
                         logger=CSVLogger(str(save_dir), name='logs'),
                         log_every_n_steps=10)
    trainer.fit(model, train_dataloaders=train_dl, val_dataloaders=val_dl,
                ckpt_path=args.resume)

    best_model_path = checkpoint_callback.best_model_path
    print('Best checkpoint:', best_model_path)
    model = PLMaskCNNAcc.load_from_checkpoint(best_model_path)
    model.eval()

    print('Generating artifacts...')
    from rsc.artifacts import ArtifactGenerator
    from rsc.artifacts.confusion_matrix_handler import ConfusionMatrixHandler
    from rsc.artifacts.accuracy_obsc_handler import AccuracyObscHandler
    from rsc.artifacts.obsc_compare_handler import ObscCompareHandler
    from rsc.artifacts.samples_handler import SamplesHandler
    artifacts_dir = save_dir / 'artifacts'
    generator = ArtifactGenerator(artifacts_dir, model, val_dl)
    generator.add_handler(ConfusionMatrixHandler(simple=False))
    generator.add_handler(ConfusionMatrixHandler(simple=True))
    generator.add_handler(AccuracyObscHandler())
    generator.add_handler(ObscCompareHandler())
    generator.add_handler(SamplesHandler())
    generator.run(raise_on_error=False)
    print('Artifacts in', artifacts_dir)
