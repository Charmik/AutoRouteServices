# Sourced by every pipeline: where the code and the data are.
#   SURFACE_ML_DATA  data root (default /home/charm/disk/surface_ML_data)
#   OSM_PBF_DIR      where the Geofabrik continent extracts live (default /home/charm/disk)
S=$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)     # surface_ML/scripts in this repo
export SURFACE_ML_DATA=${SURFACE_ML_DATA:-/home/charm/disk/surface_ML_data}
D=$SURFACE_ML_DATA
P=$D/venv/bin/python
NAIP=$D/naip; SUS=$D/susformer; E=$D/esri; OSM=$D/osm
OSM_PBF_DIR=${OSM_PBF_DIR:-/home/charm/disk}
