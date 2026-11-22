#!/bin/bash
set -e
source "$(dirname "$0")/../env.sh"
cd $E/check
nice -n 10 osmium extract -O -b 32.2,34.5,34.65,35.72 -o cy.osm.pbf $OSM_PBF_DIR/europe-latest.osm.pbf
nice -n 10 osmium tags-filter -O cy.osm.pbf w/highway -o cy_hw.osm.pbf
nice -n 10 osmium export -O -c $E/osm/export_cfg.json -f geojsonseq cy_hw.osm.pbf -o cy_hw.geojsonseq
nice -n 10 osmium extract -O -p $OSM/us.poly -o us_hw.osm.pbf $OSM/na_hw.osm.pbf
nice -n 10 osmium tags-filter -O -i us_hw.osm.pbf w/surface -o us_hw_nosurf.osm.pbf
nice -n 10 osmium export -O -c $E/osm/export_cfg.json -f geojsonseq us_hw_nosurf.osm.pbf -o us_nosurf.geojsonseq
echo DONE
