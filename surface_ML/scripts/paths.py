""" Where surface_ML keeps its data (downloads, datasets, checkpoints, predictions).
    Code lives in the AutoRouteServices repo; data lives here. Override with SURFACE_ML_DATA.
"""
import os
import pathlib

DATA = pathlib.Path(os.environ.get('SURFACE_ML_DATA', '/home/charm/disk/surface_ML_data'))
NAIP = DATA / 'naip'               # MaskCNN on NAIP: chips, datasets, checkpoints, eval
SUS = DATA / 'susformer'           # SUSformer on NAIP: windows, fine-tune checkpoints, eval
ESRI = DATA / 'esri'               # Esri World Imagery: regions, tile cache, checkpoints, check sets
OSM = DATA / 'osm'                 # OSM extracts for the NAIP (US) work
UPSTREAM_MASKCNN = DATA / 'upstream' / 'road_surface_classifier'     # github.com/jdalrym2/road_surface_classifier + patches/
UPSTREAM_SUS = DATA / 'upstream' / 'giscience'     # github.com/GIScience/Road-surface-classification-for-FAIR (+ LFS weights)
