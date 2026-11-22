# Results

All numbers are paved/unpaved accuracy against **current OSM surface tags**, with the tag hidden
from the model. OSM tags are themselves wrong for a share of roads (about a third of the confident
"errors" we looked at), so these are lower bounds.

## 1. NAIP, USA (Nov 2026)

11,792 held-out roads (spatial split), natural paved/unpaved mix.

| Approach | Accuracy | Surest 80% of roads |
|---|---|---|
| MaskCNN retrained (best checkpoint) | 95.4% | |
| MaskCNN 3-checkpoint ensemble + flips | 95.8% | 99.35% |
| … + OSM tags and location (stacker) | 96.4% | 99.6% |
| SUSformer zero-shot (as released, 30 m patch) | 85.1% | |
| SUSformer fine-tuned on NAIP, 30 m, flips | **97.2%** | 99.7% |
| SUSformer + MaskCNN + tags (stacker) | **97.6%** | 99.86% |
| "paved only if both models say paved" | 96.7% (paved precision 98.7%) | |

- **Training label age:** recent-only, imagery-matched and label-cleaned training subsets all
  landed within noise of each other (94.5–94.8%).
- **Error review:** about a third of confident errors look like wrong OSM tags.

Full report: https://claude.ai/artifact/VSPcUwav4fAXcrbrDA4JGq (builder in `report/`).

## 2. Esri World Imagery, common test across 5 regions

The SUSformer architecture fine-tuned on Esri windows (60 m north-up, z19, falling back to z18).
Test sets have 1,500 roads per region, balanced paved/unpaved; the US uses 4,000 of the NAIP val
roads. Full table: `results/esri/summary.csv`.

| Region | Zero-shot | NAIP-tuned | Esri round 1 (18k roads) | **Esri round 2 (82.5k roads)** | Round 2, surest 80% |
|---|---|---|---|---|---|
| US | 92.4 | 93.7 | 96.1 | 95.9 | 99.3 |
| Provence (FR) | 89.6 | 86.4 | 94.1 | 94.9 | 99.0 |
| Bavaria (DE) | 85.6 | 74.7 | 92.5 | 93.0 | 97.8 |
| Victoria (AU) | 90.4 | 90.9 | 92.8 | 93.5 | 98.3 |
| Hokkaido (JP) | 88.1 | 79.6 | 92.3 | 92.7 | 97.3 |

- **NAIP vs Esri on the same 4,000 US roads:** NAIP SUSformer scores 97.4%. NAIP is the better
  imagery where it exists.
- **Adding OSM tags (stacker):** +0.5 to +0.9 points, except in Victoria.
- **More training data barely helps.** Round 2 has 4.5× the roads of round 1 but gains only
  +0.4 to +0.8 points. What limits accuracy is trees hiding the road and wrong OSM tags.
- **Image age matters little**, including imagery newer than the last OSM edit.

## 3. Cyprus, every way (never in training)

147,463 ways: 81,559 with no surface tag, 65,904 tagged paved/unpaved (75.6% of them paved). No
flip averaging (4× faster on CPU, −0.2 points on the 1,500-road Cyprus test: 92.07% vs 92.27%).

- **Tagged ways at a 0.5 cut-off:** 90.6% agree with OSM. That's lower than the balanced test
  because it's the natural mix, full of service and unclassified roads.
- **Untagged ways:** 30.9% predicted paved. 61% of the predictions are confident
  (p ≤ 0.1 or ≥ 0.9).

Accuracy vs coverage on the tagged ways (undecided = between the two cut-offs):

| Unpaved if p(paved) ≤ | Paved if ≥ | Decided | Accuracy on decided | "Paved" correct | "Unpaved" correct | Untagged decided |
|---|---|---|---|---|---|---|
| 0.10 | 0.90 | 74.4% | 97.3% | 99.7% | 91.6% | 61.3% |
| 0.15 | 0.85 | 83.1% | 95.8% | 99.5% | 87.1% | 73.1% |
| 0.20 | 0.80 | 87.6% | 94.8% | 99.4% | 84.1% | 79.8% |
| 0.30 | 0.70 | 93.1% | 93.1% | 99.2% | 79.6% | 88.4% |
| 0.50 | 0.50 | 100% | 90.6% | 98.7% | 73.4% | 100% |
| **0.15** | **0.70** | 89.1% | 95.8% | 99.2% | 87.1% | 79.7% |

The paved side can be widened a lot: "paved" stays at least 99% correct down to 0.7. The unpaved
side can't: "unpaved" calls get much less reliable as soon as the cut-off moves above 0.1.

Per road type, the cut-off needed for ≥99% / ≥98% paved precision (Cyprus tagged ways):

| Road type | ≥99% | ≥98% | Untagged ways it would upgrade |
|---|---|---|---|
| residential | 0.50 | 0.50 | 15,577 of 26,149 (2,543 km) |
| unclassified | 0.89 | 0.79 | 438–704 of 4,098 |
| service | not reached | 0.95 | 477 of 14,845 |
| cycleway | not reached | 0.93 | 109 of 414 |
| track, path | not reached | not reached | none |

## 4. Planet disk estimate (Esri z19)

Extrapolated from tile counts in 4 regions and the global way counts on taginfo (Nov 2026):
~232 M ways (main roads through paths) need ~1.4 B z19 tiles (range 0.97–2.1 B). At
12.5 KB/tile that's **~17 TB (12–26 TB)**. Main roads alone are ~2 TB; tracks are the expensive
part. Streaming the imagery (fetch, predict, discard) needs only ~5 GB, for the predictions.
Check Esri's licence before bulk downloading.
