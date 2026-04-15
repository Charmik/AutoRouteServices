#!/bin/bash
set -ex

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd ~/disk/share
rm -rf heigit_road_surface_data
mkdir -p heigit_road_surface_data
cd heigit_road_surface_data

python3 ~/data/AutoRouteServices/heigit/scrape_heigit_datasets.py

for link in $(cat "geojson_links.txt"); do
  curl -OL --fail --retry 3 --retry-delay 5 --retry-max-time 120 "$link"
done

echo "Download complete!"
