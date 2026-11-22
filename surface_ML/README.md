# surface_ML — paved / unpaved from aerial imagery

Predicts whether an OSM way is **paved or unpaved** from aerial imagery, so AutoRoute can stop
treating every untagged road as unpaved. Three models were tried. One fine-tuned on Esri World
Imagery is the only one that works worldwide.

| Model | Imagery | Coverage | Accuracy (hide-the-tag test) |
|---|---|---|---|
| MaskCNN (jdalrym2/road_surface_classifier), retrained | NAIP 4-band, 1 m | USA only | 95.8% (96.4% with OSM tags) |
| SUSformer (GIScience, DINOv3), fine-tuned | NAIP RGB, 0.6 m | USA only | 97.2% (97.6% with MaskCNN and tags) |
| **SUSformer fine-tuned on Esri** (`results_r2`) | Esri World Imagery z19/z18 | worldwide | 92.7–95.9% by region; Cyprus (never trained on) 92.3% |

Results, and how accuracy trades against coverage, are in [docs/RESULTS.md](docs/RESULTS.md).
How to plug the model into AutoRoute is in [docs/AUTOROUTE.md](docs/AUTOROUTE.md).

## Code here, data there

Only code and docs live in this repo. Everything downloaded or generated is in
**`$SURFACE_ML_DATA`** (default `/home/charm/disk/surface_ML_data`). That covers imagery, tiles,
datasets, checkpoints, predictions and pages, about 82 GB today. Python reads the location from
[scripts/paths.py](scripts/paths.py); shell reads it from [pipelines/env.sh](pipelines/env.sh).
Point it somewhere else with `export SURFACE_ML_DATA=/path`.

```
surface_ML/
  scripts/      Python pipeline: prep, fetch, train, eval, check-page builder (paths.py = data root)
  pipelines/    bash runs that produced every result; env.sh sets the paths
    naip/       MaskCNN on NAIP (features -> chips -> probmasks -> dataset -> train -> eval)
    susformer/  SUSformer on NAIP (windows -> zero-shot -> fine-tune -> combine)
    esri/       Esri common test across 5 regions, rounds 1 and 2
    check/      manual-validation sets and the whole-of-Cyprus run
  web/          the manual-check pages (check/ = samples for CY/DE/US, cyprus/ = every Cyprus way)
  report/       builders and templates of the NAIP comparison report
  patches/      two small fixes to the upstream MaskCNN repo (CPU support, confusion-matrix labels)
  results/      small summary CSVs of the Esri test
  docs/         RESULTS.md, AUTOROUTE.md

$SURFACE_ML_DATA/
  venv/                         Python 3.12 env (requirements.txt)
  upstream/road_surface_classifier/   jdalrym2 clone + patches/road_surface_classifier.patch
  upstream/giscience/           GIScience SUSformer clone with LFS weights (data/weights/{head.pt,enc/encoder.pt,*.onnx})
  naip/                         NAIP chips (data/), datasets, results*/ checkpoints, eval/
  susformer/                    NAIP windows train/ val/, results_ft/ checkpoints, eval CSVs
  esri/
    osm/                        regional OSM extracts (geojsonseq)
    <region>/{test,train,train20k}/   windows/*.jpg + windows.csv + imagery_meta.csv
    tiles/{z}/{x}/{y}.jpg       raw Esri tile cache (lazy; {y}.missing = Esri has no tile)
    results_{naipinit,release,r2}/    Esri fine-tunes; best = results_r2/20261119_131313Z/sus-epoch=02-val_acc=0.93443.ckpt
    pred/, eval/                per-approach predictions and the summary
    check/                      check sets, cy_all (every Cyprus way), site/ (served pages)
    planet/                     tile-count inputs for the planet disk estimate
  osm/                          US highway extracts and us.poly
  report/                       error sheets and the generated report HTML
  scratch/                      early smoke tests
```

## Setup from scratch

```bash
D=/home/charm/disk/surface_ML_data      # or your own; export SURFACE_ML_DATA=$D
python3.12 -m venv $D/venv && $D/venv/bin/pip install -r requirements.txt
#   GDAL==3.8.4 needs the matching system libgdal-dev (apt). torch is the +cpu build.

mkdir -p $D/upstream
git clone https://github.com/jdalrym2/road_surface_classifier $D/upstream/road_surface_classifier
git -C $D/upstream/road_surface_classifier checkout e922314
git -C $D/upstream/road_surface_classifier apply $PWD/patches/road_surface_classifier.patch

git clone https://github.com/GIScience/Road-surface-classification-for-FAIR $D/upstream/giscience
git -C $D/upstream/giscience checkout f1d2547
#   The weights are Git LFS. Without git-lfs, fetch each pointer from
#   https://media.githubusercontent.com/media/GIScience/Road-surface-classification-for-FAIR/main/data/weights/<file>
#   then unzip dinov3_encoder.zip into data/weights/enc/ (encoder.pt). DINOv3 licence applies to the weights.
```

The OSM inputs are Geofabrik extracts (`europe-latest`, `asia-latest`, `australia-oceania-latest`,
`north-america-latest`). They're read from `$OSM_PBF_DIR` (default `/home/charm/disk`) and need `osmium`.

## Running

Every pipeline sources `pipelines/env.sh`, which sets `$S` (scripts), `$P` (venv python), `$D`,
`$NAIP`, `$SUS`, `$E` and `$OSM`. They are the exact runs behind the results. Some of them start
by waiting on a PID file from the run before, so run them in order or delete those wait lines.

**Predict paved/unpaved for any set of roads with the Esri model.** This is the useful one:

```bash
source pipelines/env.sh; cd $S
CK="$E/results_r2/20261119_131313Z/sus-epoch=02-val_acc=0.93443.ckpt"
$P sample_roads.py region_hw.geojsonseq all roads.csv                   # every way the model covers (or: untagged / tagged)
for i in $(seq 0 6); do $P esri_fetch.py roads.csv out --workers 32 --shard $i/7 & done; wait
$P esri_fetch.py --merge out                                             # windows.csv, imagery_meta.csv, fetch_errors.csv
$P gis_eval.py "$CK" out roads.csv pred.csv --patch-m 30 --threads 8     # add --tta for +0.2 pt at 4x the time
```

- **Input:** `region_hw.geojsonseq` is `osmium tags-filter w/highway` followed by
  `osmium export -c $E/osm/export_cfg.json -f geojsonseq`. See `pipelines/check/run_extract.sh`.
- **Output:** `pred.csv` has `osm_id, p_unpaved, n_patches`. `p_paved = 1 - p_unpaved`.
- **Download (`esri_fetch.py`):**
  - It retries each request (honouring `Retry-After` on 429/503).
  - Failed roads go to `fetch_errors*.csv` and get 2 more passes.
  - It exits 1 if any road still fails.
  - It's resumable, so rerunning only fetches what's missing.
  - Raw tiles are read from `$E/tiles` when they are already there.
  - `--tiles-only` fills the tile cache without writing windows.
- **Speed on this 8-core, CPU-only box:**
  - Fetching runs at about 235 roads/s with 7 shards.
  - Prediction runs at about 15 roads/s without TTA, or about 4/s with it.
  - Cyprus (147k ways) took 10 minutes to fetch and 2.7 h to predict.

**Rebuild and serve the check pages:**

```bash
$P build_check.py $E/check/site samples          # CY/DE/US 1,500-road samples -> roads.json + sheets/
$P build_check.py $E/check/site/cyprus cy_all    # every Cyprus way
cp ../web/check/index.html $E/check/site/; cp ../web/cyprus/index.html $E/check/site/cyprus/
cd $E/check/site && python3 -m http.server 8090  # currently http://88.99.161.250:8090/ and /cyprus/
```

The pages can save manual verdicts only when they're published as claude.ai artifacts (they use
the `db` capability). On plain http the buttons are disabled.

**Reproduce the experiments:**

| Pipeline | What it produces |
|---|---|
| `pipelines/naip/run_bin.sh`, `run_exp.sh`, `run_clean.sh`, `run_final.sh` | MaskCNN paved/unpaved and its experiments |
| `pipelines/susformer/run_gis.sh`, `run_ft.sh 30`, `run_ens.sh` | SUSformer on NAIP |
| `pipelines/esri/run_extract_regions.sh`, `run_fetch_us.sh`, `run_esri.sh`, `run_round2.sh` | Esri common test, rounds 1 and 2 → `$E/eval/summary.csv` |
| `pipelines/check/run_extract.sh`, `run_check.sh`, `run_cy_all.sh`, `run_cy_pred.sh` | check sets and whole-Cyprus predictions |

## Things to know

- **Esri terms.** The live World Imagery tile service is meant for display. Bulk download or
  caching for a planet-scale run probably needs a licence, so check before scaling up. The
  planet estimate is ~1.4 B z19 tiles, ~17 TB (range 12–26 TB), and ~232 M ways.
- **NAIP** comes from Microsoft Planetary Computer. The SAS token it hands out can be close to
  expiry; `fetch_chips.py` reads `msft:expiry` and refreshes it.
- **Labels** are current OSM tags and are noisy. About a third of the model's confident
  "errors" are wrong OSM tags, so every accuracy number here is a lower bound.
- **Test protocol.** Spatial split on 0.2° cells (25% of cells held out, crc32 hash), 1,500
  test roads per region balanced paved/unpaved; the US uses 4,000 of the NAIP val roads.
  Ways need to be at least 20 m long and exclude `access=private`, `area=yes`, and
  `service=alley|driveway|emergency_access|parking|parking_aisle|private`.
