#!/bin/bash
set -e
source "$(dirname "$0")/../env.sh"
cd $E/osm
D=$OSM_PBF_DIR
nice -n 10 osmium extract -O -c eu.json $D/europe-latest.osm.pbf
nice -n 10 osmium extract -O -b 143.5,-38.6,146.5,-36.5 -o au_victoria.osm.pbf $D/australia-oceania-latest.osm.pbf
nice -n 10 osmium extract -O -b 139.3,41.3,145.9,45.6 -o jp_hokkaido.osm.pbf $D/asia-latest.osm.pbf
for r in fr_provence de_bavaria au_victoria jp_hokkaido; do
  nice -n 10 osmium tags-filter -O $r.osm.pbf w/highway w/surface -o ${r}_hw.osm.pbf
  nice -n 10 osmium tags-filter -O ${r}_hw.osm.pbf w/surface -o ${r}_surf.osm.pbf
  nice -n 10 osmium export -O -c export_cfg.json -f geojsonseq ${r}_surf.osm.pbf -o ${r}.geojsonseq
done
echo DONE
