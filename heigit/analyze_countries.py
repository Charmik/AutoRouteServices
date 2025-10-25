#!/usr/bin/env python3

"""
Unified OSM Surface Statistics Analyzer
Downloads countries, modifies ways, and analyzes surface tag coverage

Usage: ./analyze_countries.py [directory] [--skip-download] [--skip-modify]

Arguments:
  directory         Directory for .pbf files and output CSV (default: current directory)
  --skip-download   Skip downloading files (use existing .pbf files)
  --skip-modify     Skip modification step (only analyze)

This script:
1. Downloads OSM PBF files for specified countries to [directory]
2. Analyzes surface statistics for original files
3. Runs modify_osm_ways.py to add surface tags (if heygit_ids.txt exists)
4. Analyzes surface statistics for modified files
5. Generates surface_stats.csv in [directory]

Output file:
  - surface_stats.csv - Combined statistics with both original and modified data
    For each country, contains 2 rows:
    * Country name (original statistics)
    * Country name-modified (modified statistics)
"""

import sys
import os
import subprocess
import csv
import time
import argparse
from collections import defaultdict
import osmium
from urllib.request import urlretrieve
from urllib.error import URLError


# ============================================================================
# COUNTRY CONFIGURATION
# ============================================================================

COUNTRIES = [
    # ============================================================================
    # AFRICA
    # ============================================================================
#     ('algeria', 'https://download.geofabrik.de/africa/algeria-latest.osm.pbf'),
#     ('angola', 'https://download.geofabrik.de/africa/angola-latest.osm.pbf'),
#     ('benin', 'https://download.geofabrik.de/africa/benin-latest.osm.pbf'),
#     ('botswana', 'https://download.geofabrik.de/africa/botswana-latest.osm.pbf'),
#     ('burkina-faso', 'https://download.geofabrik.de/africa/burkina-faso-latest.osm.pbf'),
#     ('burundi', 'https://download.geofabrik.de/africa/burundi-latest.osm.pbf'),
#     ('cameroon', 'https://download.geofabrik.de/africa/cameroon-latest.osm.pbf'),
#     ('canary-islands', 'https://download.geofabrik.de/africa/canary-islands-latest.osm.pbf'),
#     ('cape-verde', 'https://download.geofabrik.de/africa/cape-verde-latest.osm.pbf'),
#     ('central-african-republic', 'https://download.geofabrik.de/africa/central-african-republic-latest.osm.pbf'),
#     ('chad', 'https://download.geofabrik.de/africa/chad-latest.osm.pbf'),
#     ('comoros', 'https://download.geofabrik.de/africa/comoros-latest.osm.pbf'),
#     ('congo-brazzaville', 'https://download.geofabrik.de/africa/congo-brazzaville-latest.osm.pbf'),
#     ('congo-democratic-republic', 'https://download.geofabrik.de/africa/congo-democratic-republic-latest.osm.pbf'),
#     ('djibouti', 'https://download.geofabrik.de/africa/djibouti-latest.osm.pbf'),
#     ('egypt', 'https://download.geofabrik.de/africa/egypt-latest.osm.pbf'),
#     ('equatorial-guinea', 'https://download.geofabrik.de/africa/equatorial-guinea-latest.osm.pbf'),
#     ('eritrea', 'https://download.geofabrik.de/africa/eritrea-latest.osm.pbf'),
#     ('ethiopia', 'https://download.geofabrik.de/africa/ethiopia-latest.osm.pbf'),
#     ('gabon', 'https://download.geofabrik.de/africa/gabon-latest.osm.pbf'),
#     ('ghana', 'https://download.geofabrik.de/africa/ghana-latest.osm.pbf'),
#     ('guinea', 'https://download.geofabrik.de/africa/guinea-latest.osm.pbf'),
#     ('guinea-bissau', 'https://download.geofabrik.de/africa/guinea-bissau-latest.osm.pbf'),
#     ('ivory-coast', 'https://download.geofabrik.de/africa/ivory-coast-latest.osm.pbf'),
#     ('kenya', 'https://download.geofabrik.de/africa/kenya-latest.osm.pbf'),
#     ('lesotho', 'https://download.geofabrik.de/africa/lesotho-latest.osm.pbf'),
#     ('liberia', 'https://download.geofabrik.de/africa/liberia-latest.osm.pbf'),
#     ('libya', 'https://download.geofabrik.de/africa/libya-latest.osm.pbf'),
#     ('madagascar', 'https://download.geofabrik.de/africa/madagascar-latest.osm.pbf'),
#     ('malawi', 'https://download.geofabrik.de/africa/malawi-latest.osm.pbf'),
#     ('mali', 'https://download.geofabrik.de/africa/mali-latest.osm.pbf'),
#     ('mauritania', 'https://download.geofabrik.de/africa/mauritania-latest.osm.pbf'),
#     ('mauritius', 'https://download.geofabrik.de/africa/mauritius-latest.osm.pbf'),
#     ('morocco', 'https://download.geofabrik.de/africa/morocco-latest.osm.pbf'),
#     ('mozambique', 'https://download.geofabrik.de/africa/mozambique-latest.osm.pbf'),
#     ('namibia', 'https://download.geofabrik.de/africa/namibia-latest.osm.pbf'),
#     ('niger', 'https://download.geofabrik.de/africa/niger-latest.osm.pbf'),
#     ('nigeria', 'https://download.geofabrik.de/africa/nigeria-latest.osm.pbf'),
#     ('rwanda', 'https://download.geofabrik.de/africa/rwanda-latest.osm.pbf'),
#     ('saint-helena-ascension-tristan-da-cunha', 'https://download.geofabrik.de/africa/saint-helena-ascension-tristan-da-cunha-latest.osm.pbf'),
#     ('sao-tome-and-principe', 'https://download.geofabrik.de/africa/sao-tome-and-principe-latest.osm.pbf'),
#     ('senegal-and-gambia', 'https://download.geofabrik.de/africa/senegal-and-gambia-latest.osm.pbf'),
#     ('seychelles', 'https://download.geofabrik.de/africa/seychelles-latest.osm.pbf'),
#     ('sierra-leone', 'https://download.geofabrik.de/africa/sierra-leone-latest.osm.pbf'),
#     ('somalia', 'https://download.geofabrik.de/africa/somalia-latest.osm.pbf'),
#     ('south-africa', 'https://download.geofabrik.de/africa/south-africa-latest.osm.pbf'),
#     ('south-sudan', 'https://download.geofabrik.de/africa/south-sudan-latest.osm.pbf'),
#     ('sudan', 'https://download.geofabrik.de/africa/sudan-latest.osm.pbf'),
#     ('tanzania', 'https://download.geofabrik.de/africa/tanzania-latest.osm.pbf'),
#     ('togo', 'https://download.geofabrik.de/africa/togo-latest.osm.pbf'),
#     ('tunisia', 'https://download.geofabrik.de/africa/tunisia-latest.osm.pbf'),
#     ('uganda', 'https://download.geofabrik.de/africa/uganda-latest.osm.pbf'),
#     ('zambia', 'https://download.geofabrik.de/africa/zambia-latest.osm.pbf'),
#     ('zimbabwe', 'https://download.geofabrik.de/africa/zimbabwe-latest.osm.pbf'),
#
#     # ============================================================================
#     # ANTARCTICA
#     # ============================================================================
#     ('antarctica', 'https://download.geofabrik.de/antarctica-latest.osm.pbf'),
#
#     # ============================================================================
#     # ASIA
#     # ============================================================================
#     ('afghanistan', 'https://download.geofabrik.de/asia/afghanistan-latest.osm.pbf'),
#     ('armenia', 'https://download.geofabrik.de/asia/armenia-latest.osm.pbf'),
#     ('azerbaijan', 'https://download.geofabrik.de/asia/azerbaijan-latest.osm.pbf'),
#     ('bangladesh', 'https://download.geofabrik.de/asia/bangladesh-latest.osm.pbf'),
#     ('bhutan', 'https://download.geofabrik.de/asia/bhutan-latest.osm.pbf'),
#     ('cambodia', 'https://download.geofabrik.de/asia/cambodia-latest.osm.pbf'),
#     ('china', 'https://download.geofabrik.de/asia/china-latest.osm.pbf'),
#     ('gcc-states', 'https://download.geofabrik.de/asia/gcc-states-latest.osm.pbf'),
#     ('india', 'https://download.geofabrik.de/asia/india-latest.osm.pbf'),
#     ('indonesia', 'https://download.geofabrik.de/asia/indonesia-latest.osm.pbf'),
#     ('iran', 'https://download.geofabrik.de/asia/iran-latest.osm.pbf'),
#     ('iraq', 'https://download.geofabrik.de/asia/iraq-latest.osm.pbf'),
#     ('israel-and-palestine', 'https://download.geofabrik.de/asia/israel-and-palestine-latest.osm.pbf'),
#     ('japan', 'https://download.geofabrik.de/asia/japan-latest.osm.pbf'),
#     ('jordan', 'https://download.geofabrik.de/asia/jordan-latest.osm.pbf'),
#     ('kazakhstan', 'https://download.geofabrik.de/asia/kazakhstan-latest.osm.pbf'),
#     ('kyrgyzstan', 'https://download.geofabrik.de/asia/kyrgyzstan-latest.osm.pbf'),
#     ('laos', 'https://download.geofabrik.de/asia/laos-latest.osm.pbf'),
#     ('lebanon', 'https://download.geofabrik.de/asia/lebanon-latest.osm.pbf'),
#     ('malaysia-singapore-brunei', 'https://download.geofabrik.de/asia/malaysia-singapore-brunei-latest.osm.pbf'),
#     ('maldives', 'https://download.geofabrik.de/asia/maldives-latest.osm.pbf'),
#     ('mongolia', 'https://download.geofabrik.de/asia/mongolia-latest.osm.pbf'),
#     ('myanmar', 'https://download.geofabrik.de/asia/myanmar-latest.osm.pbf'),
#     ('nepal', 'https://download.geofabrik.de/asia/nepal-latest.osm.pbf'),
#     ('north-korea', 'https://download.geofabrik.de/asia/north-korea-latest.osm.pbf'),
#     ('pakistan', 'https://download.geofabrik.de/asia/pakistan-latest.osm.pbf'),
#     ('philippines', 'https://download.geofabrik.de/asia/philippines-latest.osm.pbf'),
#     ('south-korea', 'https://download.geofabrik.de/asia/south-korea-latest.osm.pbf'),
#     ('sri-lanka', 'https://download.geofabrik.de/asia/sri-lanka-latest.osm.pbf'),
#     ('syria', 'https://download.geofabrik.de/asia/syria-latest.osm.pbf'),
#     ('taiwan', 'https://download.geofabrik.de/asia/taiwan-latest.osm.pbf'),
#     ('tajikistan', 'https://download.geofabrik.de/asia/tajikistan-latest.osm.pbf'),
    ('thailand', 'https://download.geofabrik.de/asia/thailand-latest.osm.pbf'),
#     ('turkmenistan', 'https://download.geofabrik.de/asia/turkmenistan-latest.osm.pbf'),
#     ('uzbekistan', 'https://download.geofabrik.de/asia/uzbekistan-latest.osm.pbf'),
#     ('vietnam', 'https://download.geofabrik.de/asia/vietnam-latest.osm.pbf'),
#     ('yemen', 'https://download.geofabrik.de/asia/yemen-latest.osm.pbf'),
#
#     # ============================================================================
#     # AUSTRALIA AND OCEANIA
#     # ============================================================================
    ('australia', 'https://download.geofabrik.de/australia-oceania/australia-latest.osm.pbf'),
#     ('cook-islands', 'https://download.geofabrik.de/australia-oceania/cook-islands-latest.osm.pbf'),
#     ('fiji', 'https://download.geofabrik.de/australia-oceania/fiji-latest.osm.pbf'),
#     ('kiribati', 'https://download.geofabrik.de/australia-oceania/kiribati-latest.osm.pbf'),
#     ('marshall-islands', 'https://download.geofabrik.de/australia-oceania/marshall-islands-latest.osm.pbf'),
#     ('micronesia', 'https://download.geofabrik.de/australia-oceania/micronesia-latest.osm.pbf'),
#     ('nauru', 'https://download.geofabrik.de/australia-oceania/nauru-latest.osm.pbf'),
#     ('new-caledonia', 'https://download.geofabrik.de/australia-oceania/new-caledonia-latest.osm.pbf'),
#     ('new-zealand', 'https://download.geofabrik.de/australia-oceania/new-zealand-latest.osm.pbf'),
#     ('niue', 'https://download.geofabrik.de/australia-oceania/niue-latest.osm.pbf'),
#     ('palau', 'https://download.geofabrik.de/australia-oceania/palau-latest.osm.pbf'),
#     ('papua-new-guinea', 'https://download.geofabrik.de/australia-oceania/papua-new-guinea-latest.osm.pbf'),
#     ('pitcairn-islands', 'https://download.geofabrik.de/australia-oceania/pitcairn-islands-latest.osm.pbf'),
#     ('samoa', 'https://download.geofabrik.de/australia-oceania/samoa-latest.osm.pbf'),
#     ('solomon-islands', 'https://download.geofabrik.de/australia-oceania/solomon-islands-latest.osm.pbf'),
#     ('tokelau', 'https://download.geofabrik.de/australia-oceania/tokelau-latest.osm.pbf'),
#     ('tonga', 'https://download.geofabrik.de/australia-oceania/tonga-latest.osm.pbf'),
#     ('tuvalu', 'https://download.geofabrik.de/australia-oceania/tuvalu-latest.osm.pbf'),
#     ('vanuatu', 'https://download.geofabrik.de/australia-oceania/vanuatu-latest.osm.pbf'),
#
#     # ============================================================================
#     # CENTRAL AMERICA
#     # ============================================================================
#     ('belize', 'https://download.geofabrik.de/central-america/belize-latest.osm.pbf'),
#     ('costa-rica', 'https://download.geofabrik.de/central-america/costa-rica-latest.osm.pbf'),
#     ('el-salvador', 'https://download.geofabrik.de/central-america/el-salvador-latest.osm.pbf'),
#     ('guatemala', 'https://download.geofabrik.de/central-america/guatemala-latest.osm.pbf'),
#     ('honduras', 'https://download.geofabrik.de/central-america/honduras-latest.osm.pbf'),
#     ('nicaragua', 'https://download.geofabrik.de/central-america/nicaragua-latest.osm.pbf'),
#     ('panama', 'https://download.geofabrik.de/central-america/panama-latest.osm.pbf'),
#
#     # ============================================================================
#     # EUROPE
#     # ============================================================================
    ('albania', 'https://download.geofabrik.de/europe/albania-latest.osm.pbf'),
#     ('andorra', 'https://download.geofabrik.de/europe/andorra-latest.osm.pbf'),
    ('austria', 'https://download.geofabrik.de/europe/austria-latest.osm.pbf'),
#     ('azores', 'https://download.geofabrik.de/europe/azores-latest.osm.pbf'),
#     ('belarus', 'https://download.geofabrik.de/europe/belarus-latest.osm.pbf'),
    ('belgium', 'https://download.geofabrik.de/europe/belgium-latest.osm.pbf'),
    ('bosnia-herzegovina', 'https://download.geofabrik.de/europe/bosnia-herzegovina-latest.osm.pbf'),
    ('bulgaria', 'https://download.geofabrik.de/europe/bulgaria-latest.osm.pbf'),
    ('croatia', 'https://download.geofabrik.de/europe/croatia-latest.osm.pbf'),
    ('cyprus', 'https://download.geofabrik.de/europe/cyprus-latest.osm.pbf'),
    ('czech-republic', 'https://download.geofabrik.de/europe/czech-republic-latest.osm.pbf'),
    ('denmark', 'https://download.geofabrik.de/europe/denmark-latest.osm.pbf'),
    ('estonia', 'https://download.geofabrik.de/europe/estonia-latest.osm.pbf'),
#     ('faroe-islands', 'https://download.geofabrik.de/europe/faroe-islands-latest.osm.pbf'),
    ('finland', 'https://download.geofabrik.de/europe/finland-latest.osm.pbf'),
    ('france', 'https://download.geofabrik.de/europe/france-latest.osm.pbf'),
#     ('georgia', 'https://download.geofabrik.de/europe/georgia-latest.osm.pbf'),
    ('germany', 'https://download.geofabrik.de/europe/germany-latest.osm.pbf'),
    ('greece', 'https://download.geofabrik.de/europe/greece-latest.osm.pbf'),
#     ('guernsey-jersey', 'https://download.geofabrik.de/europe/guernsey-jersey-latest.osm.pbf'),
#     ('hungary', 'https://download.geofabrik.de/europe/hungary-latest.osm.pbf'),
#     ('iceland', 'https://download.geofabrik.de/europe/iceland-latest.osm.pbf'),
#     ('ireland-and-northern-ireland', 'https://download.geofabrik.de/europe/ireland-and-northern-ireland-latest.osm.pbf'),
#     ('isle-of-man', 'https://download.geofabrik.de/europe/isle-of-man-latest.osm.pbf'),
    ('italy', 'https://download.geofabrik.de/europe/italy-latest.osm.pbf'),
#     ('kosovo', 'https://download.geofabrik.de/europe/kosovo-latest.osm.pbf'),
#     ('latvia', 'https://download.geofabrik.de/europe/latvia-latest.osm.pbf'),
#     ('liechtenstein', 'https://download.geofabrik.de/europe/liechtenstein-latest.osm.pbf'),
#     ('lithuania', 'https://download.geofabrik.de/europe/lithuania-latest.osm.pbf'),
#     ('luxembourg', 'https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf'),
#     ('macedonia', 'https://download.geofabrik.de/europe/macedonia-latest.osm.pbf'),
#     ('malta', 'https://download.geofabrik.de/europe/malta-latest.osm.pbf'),
#     ('moldova', 'https://download.geofabrik.de/europe/moldova-latest.osm.pbf'),
#     ('monaco', 'https://download.geofabrik.de/europe/monaco-latest.osm.pbf'),
#     ('montenegro', 'https://download.geofabrik.de/europe/montenegro-latest.osm.pbf'),
#     ('netherlands', 'https://download.geofabrik.de/europe/netherlands-latest.osm.pbf'),
#     ('norway', 'https://download.geofabrik.de/europe/norway-latest.osm.pbf'),
#     ('poland', 'https://download.geofabrik.de/europe/poland-latest.osm.pbf'),
    ('portugal', 'https://download.geofabrik.de/europe/portugal-latest.osm.pbf'),
#     ('romania', 'https://download.geofabrik.de/europe/romania-latest.osm.pbf'),
#     ('russia', 'https://download.geofabrik.de/russia-latest.osm.pbf'),
#     ('serbia', 'https://download.geofabrik.de/europe/serbia-latest.osm.pbf'),
#     ('slovakia', 'https://download.geofabrik.de/europe/slovakia-latest.osm.pbf'),
#     ('slovenia', 'https://download.geofabrik.de/europe/slovenia-latest.osm.pbf'),
    ('spain', 'https://download.geofabrik.de/europe/spain-latest.osm.pbf'),
#     ('sweden', 'https://download.geofabrik.de/europe/sweden-latest.osm.pbf'),
    ('switzerland', 'https://download.geofabrik.de/europe/switzerland-latest.osm.pbf'),
#     ('turkey', 'https://download.geofabrik.de/europe/turkey-latest.osm.pbf'),
#     ('ukraine', 'https://download.geofabrik.de/europe/ukraine-latest.osm.pbf'),
    ('united-kingdom', 'https://download.geofabrik.de/europe/great-britain-latest.osm.pbf'),
#
#     # ============================================================================
#     # NORTH AMERICA
#     # ============================================================================
    ('canada', 'https://download.geofabrik.de/north-america/canada-latest.osm.pbf'),
#     ('greenland', 'https://download.geofabrik.de/north-america/greenland-latest.osm.pbf'),
#     ('mexico', 'https://download.geofabrik.de/north-america/mexico-latest.osm.pbf'),
    ('usa', 'https://download.geofabrik.de/north-america/us-latest.osm.pbf'),
#
#     # ============================================================================
#     # SOUTH AMERICA
#     # ============================================================================
    ('argentina', 'https://download.geofabrik.de/south-america/argentina-latest.osm.pbf'),
#     ('bolivia', 'https://download.geofabrik.de/south-america/bolivia-latest.osm.pbf'),
#     ('brazil', 'https://download.geofabrik.de/south-america/brazil-latest.osm.pbf'),
#     ('chile', 'https://download.geofabrik.de/south-america/chile-latest.osm.pbf'),
#     ('colombia', 'https://download.geofabrik.de/south-america/colombia-latest.osm.pbf'),
#     ('ecuador', 'https://download.geofabrik.de/south-america/ecuador-latest.osm.pbf'),
#     ('falkland-islands', 'https://download.geofabrik.de/south-america/falkland-islands-latest.osm.pbf'),
#     ('french-guiana', 'https://download.geofabrik.de/south-america/french-guiana-latest.osm.pbf'),
#     ('guyana', 'https://download.geofabrik.de/south-america/guyana-latest.osm.pbf'),
#     ('paraguay', 'https://download.geofabrik.de/south-america/paraguay-latest.osm.pbf'),
#     ('peru', 'https://download.geofabrik.de/south-america/peru-latest.osm.pbf'),
#     ('suriname', 'https://download.geofabrik.de/south-america/suriname-latest.osm.pbf'),
#     ('uruguay', 'https://download.geofabrik.de/south-america/uruguay-latest.osm.pbf'),
#     ('venezuela', 'https://download.geofabrik.de/south-america/venezuela-latest.osm.pbf'),
]


# ============================================================================
# SURFACE STATISTICS COLLECTOR (from file_surface_stats.py)
# ============================================================================

class SurfaceStatsCollector(osmium.SimpleHandler):
    """Handler to collect surface statistics for highway ways"""

    def __init__(self):
        super().__init__()
        self.stats = defaultdict(lambda: {'with_surface': 0, 'total': 0})
        self.highway_types = [
            'primary', 'primary_link',
            'trunk', 'trunk_link',
            'secondary', 'secondary_link',
            'tertiary', 'tertiary_link',
            'residential',
            'unclassified',
            'service',
            'track',
            'cycleway'
        ]
        self.way_count = 0
        self.highway_way_count = 0

    def way(self, w):
        """Process each way in the file"""
        self.way_count += 1

        highway = None
        has_surface = False

        for tag in w.tags:
            if tag.k == 'highway':
                highway = tag.v
            elif tag.k == 'surface':
                has_surface = True

        if highway:
            highway_normalized = highway
            if highway.endswith('_link'):
                highway_normalized = highway[:-5]

            if highway_normalized in ['primary', 'trunk', 'secondary', 'tertiary',
                                     'residential', 'unclassified', 'service', 'track', 'cycleway']:
                self.highway_way_count += 1
                self.stats[highway_normalized]['total'] += 1

                if has_surface:
                    self.stats[highway_normalized]['with_surface'] += 1

        if self.way_count % 10000 == 0:
            print(f"    Processed {self.way_count:,} ways ({self.highway_way_count:,} highway ways)...",
                  end='\r', flush=True)


def calculate_percentage_without_surface(stats):
    """Calculate average percentage of important roads WITHOUT surface tag"""
    main_road_types = ['secondary', 'tertiary', 'unclassified', 'cycleway']
    total_main_roads = 0
    total_without_surface = 0

    for highway_type in main_road_types:
        if highway_type in stats:
            total = stats[highway_type]['total']
            with_surface = stats[highway_type]['with_surface']
            without_surface = total - with_surface
            total_main_roads += total
            total_without_surface += without_surface

    if total_main_roads == 0:
        return 0.0

    percentage = (total_without_surface / total_main_roads) * 100
    return round(percentage, 1)


def analyze_pbf(pbf_file, country_name):
    """Analyze a PBF file and return statistics"""
    print(f"    Analyzing: {pbf_file}")

    if not os.path.isfile(pbf_file):
        print(f"    ✗ Error: File not found")
        return None

    handler = SurfaceStatsCollector()

    try:
        handler.apply_file(pbf_file, locations=False)
        print(f"\r    ✓ Analyzed {handler.way_count:,} ways ({handler.highway_way_count:,} highway ways)" + " " * 20)

        return {
            'country': country_name.capitalize(),
            'stats': handler.stats,
            'filename': pbf_file
        }
    except Exception as e:
        print(f"    ✗ Error: {e}")
        return None


# ============================================================================
# DOWNLOAD AND FILE MANAGEMENT
# ============================================================================

def download_country(country_name, url, data_dir, skip_download=False):
    """Download country PBF file if it doesn't exist"""
    filename = f"{country_name}-latest.osm.pbf"
    filepath = os.path.join(data_dir, filename)

    if os.path.exists(filepath):
        size_mb = os.path.getsize(filepath) / (1024 * 1024)
        print(f"  ✓ Already downloaded: {filepath} ({size_mb:.2f} MB)")
        return filepath

    if skip_download:
        print(f"  ✗ File not found and --skip-download enabled: {filepath}")
        return None

    print(f"  Downloading: {url}")
    print(f"  Saving to: {filepath}")

    try:
        def progress_hook(block_num, block_size, total_size):
            downloaded = block_num * block_size
            if total_size > 0:
                percent = min(downloaded * 100 / total_size, 100)
                mb_downloaded = downloaded / (1024 * 1024)
                mb_total = total_size / (1024 * 1024)
                print(f"    Progress: {percent:.1f}% ({mb_downloaded:.1f}/{mb_total:.1f} MB)",
                      end='\r', flush=True)

        urlretrieve(url, filepath, reporthook=progress_hook)
        print()  # New line after progress

        size_mb = os.path.getsize(filepath) / (1024 * 1024)
        print(f"  ✓ Downloaded: {filepath} ({size_mb:.2f} MB)")
        return filepath

    except URLError as e:
        print(f"  ✗ Download failed: {e}")
        return None
    except Exception as e:
        print(f"  ✗ Error: {e}")
        return None


def run_modify_osm_ways(pbf_file, ids_file, skip_modify=False):
    """Run modify_osm_ways.py on the PBF file"""
    if skip_modify:
        print(f"  ⊘ Skipping modification (--skip-modify enabled)")
        return None

    if not os.path.exists(ids_file):
        print(f"  ⊘ Skipping modification (no {ids_file} found)")
        return None

    # Generate output filename
    if pbf_file.endswith('.osm.pbf'):
        output_file = pbf_file[:-8] + '-modified.osm.pbf'
    else:
        output_file = pbf_file + '-modified.osm.pbf'

    # Check if already modified
    if os.path.exists(output_file):
        print(f"  ✓ Already modified: {output_file}")
        return output_file

    print(f"  Running modify_osm_ways.py...")

    try:
        result = subprocess.run(
            ['python3', './modify_osm_ways.py', pbf_file, ids_file],
            check=True,
            capture_output=False
        )

        if os.path.exists(output_file):
            print(f"  ✓ Modified file created: {output_file}")
            return output_file
        else:
            print(f"  ✗ Modification failed: output file not created")
            return None

    except subprocess.CalledProcessError as e:
        print(f"  ✗ Modification failed: {e}")
        return None
    except Exception as e:
        print(f"  ✗ Error running modify_osm_ways.py: {e}")
        return None


# ============================================================================
# CSV OUTPUT
# ============================================================================

def load_existing_csv_countries(csv_file):
    """Load list of countries already processed in existing CSV file
    Returns a dict with:
    - 'original': set of country names with original analysis done (lowercase)
    - 'modified': set of country names with modified analysis done (lowercase)
    """
    existing = {'original': set(), 'modified': set()}

    if not os.path.exists(csv_file):
        return existing

    try:
        with open(csv_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                country_name = row['country']
                if country_name.endswith('-modified'):
                    # Extract base country name and normalize to lowercase
                    base_name = country_name[:-9].lower()  # Remove '-modified' and lowercase
                    existing['modified'].add(base_name)
                else:
                    # Normalize to lowercase for case-insensitive comparison
                    existing['original'].add(country_name.lower())

        print(f"Loaded existing CSV: {csv_file}")
        print(f"  Countries with original analysis: {len(existing['original'])}")
        print(f"  Countries with modified analysis: {len(existing['modified'])}")
        if existing['original']:
            print(f"    {', '.join(sorted(existing['original']))}")
    except Exception as e:
        print(f"Warning: Could not read existing CSV: {e}")

    return existing


def append_country_to_csv(country_result, modified_result, output_file):
    """Append a single country's results to CSV file immediately
    Writes original row and modified row (if exists) for one country
    """
    highway_types = ['primary', 'trunk', 'secondary', 'tertiary',
                     'residential', 'unclassified', 'service', 'track', 'cycleway']

    # Check if file exists to determine if we need header
    file_exists = os.path.exists(output_file)

    # Read existing data to avoid duplicates
    existing_countries = set()
    if file_exists:
        try:
            with open(output_file, 'r') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    existing_countries.add(row['country'])
        except:
            pass

    # Open in append mode
    with open(output_file, 'a', newline='') as csvfile:
        fieldnames = ['country'] + highway_types + ['average % for main roads WITHOUT suffer']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)

        # Write header only if file is new
        if not file_exists:
            writer.writeheader()

        country = country_result['country']

        # Write original row (if not already in CSV)
        if country not in existing_countries:
            row = {'country': country}
            stats = country_result['stats']

            for highway_type in highway_types:
                if highway_type in stats:
                    total = stats[highway_type]['total']
                    with_surface = stats[highway_type]['with_surface']
                    row[highway_type] = f"{with_surface}/{total}"
                else:
                    row[highway_type] = "0/0"

            avg_pct = calculate_percentage_without_surface(stats)
            row['average % for main roads WITHOUT suffer'] = avg_pct
            writer.writerow(row)
            print(f"  → Added {country} to CSV")

        # Write modified row (if exists and not already in CSV)
        if modified_result:
            modified_country = f"{country}-modified"
            if modified_country not in existing_countries:
                row = {'country': modified_country}
                stats = modified_result['stats']

                for highway_type in highway_types:
                    if highway_type in stats:
                        total = stats[highway_type]['total']
                        with_surface = stats[highway_type]['with_surface']
                        row[highway_type] = f"{with_surface}/{total}"
                    else:
                        row[highway_type] = "0/0"

                avg_pct = calculate_percentage_without_surface(stats)
                row['average % for main roads WITHOUT suffer'] = avg_pct
                writer.writerow(row)
                print(f"  → Added {modified_country} to CSV")


def write_comparison_csv(original_results, modified_results, output_file):
    """Write comparison CSV showing before/after side by side"""
    highway_types = ['primary', 'trunk', 'secondary', 'tertiary',
                     'residential', 'unclassified', 'service', 'track', 'cycleway']

    # Create a mapping of country to results
    original_map = {r['country']: r for r in original_results}
    modified_map = {r['country']: r for r in modified_results}

    with open(output_file, 'w', newline='') as csvfile:
        fieldnames = ['country']
        for ht in highway_types:
            fieldnames.extend([f'{ht}_original', f'{ht}_modified', f'{ht}_change'])
        fieldnames.extend(['avg_pct_original', 'avg_pct_modified', 'avg_pct_change'])

        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()

        for country in original_map.keys():
            if country not in modified_map:
                continue

            orig = original_map[country]
            modi = modified_map[country]

            row = {'country': country}

            for ht in highway_types:
                orig_stats = orig['stats'].get(ht, {'with_surface': 0, 'total': 0})
                modi_stats = modi['stats'].get(ht, {'with_surface': 0, 'total': 0})

                row[f'{ht}_original'] = f"{orig_stats['with_surface']}/{orig_stats['total']}"
                row[f'{ht}_modified'] = f"{modi_stats['with_surface']}/{modi_stats['total']}"

                change = modi_stats['with_surface'] - orig_stats['with_surface']
                row[f'{ht}_change'] = f"+{change}" if change > 0 else str(change)

            orig_pct = calculate_percentage_without_surface(orig['stats'])
            modi_pct = calculate_percentage_without_surface(modi['stats'])
            pct_change = modi_pct - orig_pct

            row['avg_pct_original'] = orig_pct
            row['avg_pct_modified'] = modi_pct
            row['avg_pct_change'] = f"{pct_change:+.1f}"

            writer.writerow(row)

    print(f"✓ Comparison CSV written: {output_file}")


# ============================================================================
# FILE CLEANUP
# ============================================================================

def cleanup_pbf_files(pbf_file, modified_file=None):
    """Delete PBF files after successful CSV write to save disk space"""
    files_deleted = []

    # Delete original file
    if pbf_file and os.path.exists(pbf_file):
        try:
            size_mb = os.path.getsize(pbf_file) / (1024 * 1024)
            os.remove(pbf_file)
            files_deleted.append(f"{os.path.basename(pbf_file)} ({size_mb:.1f} MB)")
        except Exception as e:
            print(f"  ⚠ Warning: Could not delete {pbf_file}: {e}")

    # Delete modified file
    if modified_file and os.path.exists(modified_file):
        try:
            size_mb = os.path.getsize(modified_file) / (1024 * 1024)
            os.remove(modified_file)
            files_deleted.append(f"{os.path.basename(modified_file)} ({size_mb:.1f} MB)")
        except Exception as e:
            print(f"  ⚠ Warning: Could not delete {modified_file}: {e}")

    if files_deleted:
        print(f"  🗑  Cleaned up: {', '.join(files_deleted)}")


# ============================================================================
# MAIN PIPELINE
# ============================================================================

def process_country(country_name, url, data_dir, ids_file='heygit_ids.txt', skip_download=False, skip_modify=False):
    """Process a single country through the entire pipeline"""
    print(f"\n{'='*80}")
    print(f"Processing: {country_name.upper()}")
    print(f"{'='*80}")

    results = {}

    # Step 1: Download
    print(f"\n[1/4] Download")
    pbf_file = download_country(country_name, url, data_dir, skip_download)
    if not pbf_file:
        print(f"✗ Skipping {country_name} - download failed")
        return None

    # Step 2: Analyze original
    print(f"\n[2/4] Analyze Original")
    original_stats = analyze_pbf(pbf_file, country_name)
    if not original_stats:
        print(f"✗ Skipping {country_name} - analysis failed")
        return None
    results['original'] = original_stats

    # Step 3: Modify
    print(f"\n[3/4] Modify PBF")
    modified_file = run_modify_osm_ways(pbf_file, ids_file, skip_modify)

    # Step 4: Analyze modified (if modification was done)
    if modified_file and os.path.exists(modified_file):
        print(f"\n[4/4] Analyze Modified")
        modified_stats = analyze_pbf(modified_file, country_name)
        if modified_stats:
            results['modified'] = modified_stats
    else:
        print(f"\n[4/4] Analyze Modified - SKIPPED (no modified file)")

    print(f"\n✓ Completed: {country_name}")
    return results


def main():
    """Main execution pipeline"""
    # Parse arguments
    parser = argparse.ArgumentParser(
        description='OSM Surface Statistics Analyzer',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  ./analyze_countries.py                    # Use current directory
  ./analyze_countries.py data/              # Use data/ directory
  ./analyze_countries.py data/ --skip-download  # Skip downloading
        """)

    parser.add_argument('directory', nargs='?', default='.',
                       help='Directory for .pbf files and output CSV (default: current directory)')
    parser.add_argument('--skip-download', action='store_true',
                       help='Skip downloading files (use existing .pbf files)')
    parser.add_argument('--skip-modify', action='store_true',
                       help='Skip modification step (only analyze)')

    args = parser.parse_args()

    # Get and validate directory
    data_dir = os.path.abspath(args.directory)

    # Create directory if it doesn't exist
    if not os.path.exists(data_dir):
        print(f"Creating directory: {data_dir}")
        os.makedirs(data_dir)

    print("=" * 80)
    print("OSM SURFACE STATISTICS ANALYZER - UNIFIED PIPELINE")
    print("=" * 80)
    print()
    print(f"Data directory: {data_dir}")
    print(f"Countries to process: {len(COUNTRIES)}")
    for name, _ in COUNTRIES:
        print(f"  - {name}")
    print()
    print(f"Options:")
    print(f"  Skip download: {args.skip_download}")
    print(f"  Skip modify: {args.skip_modify}")
    print()

    # Check if modify_osm_ways.py exists
    if not os.path.exists('./modify_osm_ways.py'):
        print("Warning: modify_osm_ways.py not found in current directory")
        print("Modification step will be skipped")
        args.skip_modify = True

    # Load existing countries from CSV (if exists)
    output_csv = os.path.join(data_dir, 'surface_stats.csv')
    existing_countries = load_existing_csv_countries(output_csv)

    # Process each country
    all_original_results = []
    all_modified_results = []

    start_time = time.time()

    print()
    countries_processed = 0
    countries_skipped = 0

    for country_name, url in COUNTRIES:
        # Check if country already processed
        has_original = country_name in existing_countries['original']
        has_modified = country_name in existing_countries['modified']

        # Skip entirely if both original and modified are done
        if has_original and (has_modified or args.skip_modify):
            print(f"\n✓ Skipping {country_name} - already in CSV (original{' and modified' if has_modified else ''})")
            countries_skipped += 1
            continue

        # Determine what needs to be done
        need_original = not has_original
        need_modified = not has_modified and not args.skip_modify

        if need_original and not need_modified:
            print(f"\n⊙ {country_name} - will process original only (modified already in CSV)")
        elif not need_original and need_modified:
            print(f"\n⊙ {country_name} - will process modification only (original already in CSV)")

        # Process what's needed
        results = {}
        pbf_file = None
        modified_file = None

        if need_original:
            # Download and analyze original
            print(f"\n{'-'*80}")
            print(f"Country: {country_name.upper()}")
            print(f"{'-'*80}")
            print(f"\n[1/2] Download")
            pbf_file = download_country(country_name, url, data_dir, args.skip_download)

            if pbf_file:
                print(f"\n[2/2] Analyze Original")
                original_stats = analyze_pbf(pbf_file, country_name)
                if original_stats:
                    results['original'] = original_stats
                    all_original_results.append(original_stats)
            else:
                print(f"✗ Skipping {country_name} - download failed")
                continue

        if need_modified and 'original' in results or not need_original:
            # Need to get pbf_file if we didn't download in original step
            if not need_original:
                pbf_filename = f"{country_name}-latest.osm.pbf"
                pbf_file = os.path.join(data_dir, pbf_filename)

            # Modify and analyze modified
            if pbf_file and os.path.exists(pbf_file):
                print(f"\n[Modification]")
                ids_file = 'heygit_ids.txt'
                modified_file = run_modify_osm_ways(pbf_file, ids_file, skip_modify=False)

                if modified_file and os.path.exists(modified_file):
                    print(f"\n[Analyze Modified]")
                    modified_stats = analyze_pbf(modified_file, country_name)
                    if modified_stats:
                        results['modified'] = modified_stats
                        all_modified_results.append(modified_stats)

        # Write to CSV immediately if we have new results
        if results:
            print(f"\n📝 Writing to CSV: {output_csv}")
            append_country_to_csv(results.get('original'), results.get('modified'), output_csv)
            countries_processed += 1

            # Clean up .pbf files after successful CSV write
            cleanup_pbf_files(pbf_file, modified_file)

            print(f"\n✓ Completed: {country_name}")

    # Summary
    elapsed = time.time() - start_time
    print(f"\n{'='*80}")
    print("SUMMARY")
    print(f"{'='*80}")
    print(f"Data directory: {data_dir}")
    print(f"Countries in list: {len(COUNTRIES)}")
    print(f"Countries skipped (already in CSV): {countries_skipped}")
    print(f"Countries processed (new): {countries_processed}")
    print(f"  - Original analysis: {len(all_original_results)}")
    print(f"  - Modified analysis: {len(all_modified_results)}")
    print(f"Total time: {elapsed:.1f}s ({elapsed/60:.1f} minutes)")
    print()
    print("Output file:")
    print(f"  - {output_csv}")
    print(f"    Written incrementally after each country")
    if countries_processed > 0:
        print(f"    Added {countries_processed} new countries to CSV")
    else:
        print(f"    No new countries added (all were already in CSV)")
    print()
    print("✓ Done!")


if __name__ == '__main__':
    main()
