# Using the model in AutoRoute

## Today

`CompactTileBuilder.buildSurfaceMapFromWays` decides each way's surface in this order:
1. the `surface` tag;
2. otherwise `OSMGraphMapper.isGoodRoadSurface`, which checks `smoothness`, then the HeiGIT
   paved list, then the tag heuristics in `getRoadSurfaceRating`;
3. otherwise **UNPAVED**.

Tracks with no surface tag are always unpaved. This is deliberately pessimistic: calling a really
unpaved road paved is the expensive mistake.

## Goal

Turn as many of those fallback-UNPAVED ways into PAVED as possible, while keeping the share of
upgraded ways that are really unpaved small (target: paved precision ≥ 98–99%).

## Approach, in order of value

1. **Upgrade-only, per road type.** Add one step before the UNPAVED fallback: if
   `p_paved(way) >= cutoff[highway]`, mark the way PAVED. The model never makes anything
   unpaved, so only paved precision needs controlling. The simplest delivery is a list of way ids
   to treat as paved, in the same format as `heygit_ids.txt`. `ModifyOsmWays` already adds
   `surface=paved` from that list during the OSRM build, and `HeyGitSurfaceLoader` (property
   `heygit.surface.file.path`) reads a paved-ids file for
   the tile surfaces, so the ids can be merged into it or loaded alongside it. Keep the raw
   `osm_id -> p_paved` table too, so cut-offs can change without re-predicting.
   - **Starting cut-offs** (Cyprus, see RESULTS.md §3): residential 0.5–0.7, unclassified 0.8–0.9,
     service and cycleway ≥ 0.95.
   - **Never for track or path:** "paved" calls there are right only 43–58% of the time.

2. **Measure on the ways the rule actually changes.** The tables above are measured on *all*
   tagged ways, but the model will only see ways the tag rules fall through on, and those are
   likely more often unpaved. To get cut-offs that fit:
   - take tagged ways from the test regions;
   - hide `surface`;
   - run a Python port of `checkRoadSurface` (with the HeiGIT list);
   - measure precision only where it returns UNPAVED.

3. **Make PAVED harder to reach.**
   - Score each way by its *least* paved patch instead of the mean of up to 4 patches.
   - Skip the model, or raise the cut-off, for z18-only imagery, very old imagery and very short
     ways (1 patch).
   - Capture date and zoom are in `imagery_meta.csv`.

4. **Use the road's context.** Combine p_paved, highway, length, tags, the HeiGIT flag and
   connected or same-name ways' surfaces in a small logistic or gradient-boosted model. Expected
   to help most on service and unclassified ways.

5. **USA:** average the NAIP and Esri models (NAIP alone 97.4% vs Esri 95.9% on the same roads).

6. **Check by hand.** Judge about 300 randomly sampled upgraded ways on the check page. OSM
   disagreement overstates error, because ~1/3 of disagreements are wrong tags.

## Producing the table for a region

```bash
source pipelines/env.sh; cd $S
$P sample_roads.py region_hw.geojsonseq all roads.csv     # every way; keep rows with empty 'binary' for untagged only
# fetch + predict as in README "Running"; then p_paved = 1 - p_unpaved per osm_id
```
