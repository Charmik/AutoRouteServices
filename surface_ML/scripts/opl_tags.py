#!/usr/bin/env python3
""" OPL ways (osmium getid -f opl) -> CSV of the side-information tags used by stack_eval.py

    Usage: opl_tags.py ways.opl out.csv
"""
import re
import sys
from urllib.parse import unquote

import pandas as pd

TAGS = ['highway', 'tracktype', 'smoothness', 'lanes', 'maxspeed', 'oneway', 'ref', 'name',
        'bridge', 'tunnel', 'service', 'access', 'width', 'lit', 'sidewalk', 'motor_vehicle',
        'tiger:cfcc', 'tiger:reviewed', '4wd_only', 'hgv', 'foot', 'bicycle']


def opl_unescape(s):
    return re.sub(r'%([0-9a-fA-F]+)%', lambda m: chr(int(m.group(1), 16)), s)


rows = []
for line in open(sys.argv[1]):
    if not line.startswith('w'):
        continue
    f = line.split(' ')
    tagf = next((x for x in f if x.startswith('T')), 'T')[1:]
    tags = dict(opl_unescape(kv).split('=', 1) for kv in tagf.split(',') if '=' in kv)
    rows.append({'osm_id': int(f[0][1:]), 'n_tags': len(tags), **{t: tags.get(t) for t in TAGS}})
pd.DataFrame(rows).to_csv(sys.argv[2], index=False)
print(len(rows))
