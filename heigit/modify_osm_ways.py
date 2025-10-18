#!/usr/bin/env python3

"""
Script to modify OSM PBF file and add surface tags to ways listed in ids.txt
Usage: ./modify_osm_ways.py <input.pbf> <ids.txt>
Example: ./modify_osm_ways.py cyprus-latest.osm.pbf ids.txt

Format of ids.txt (each line: way_id surface_value):
55678093 paved
12345678 asphalt
98765432 gravel

Requires: osmium library (install with: pip install osmium)
"""

import sys
import os
import osmium
import time


class SurfaceUpdater(osmium.SimpleHandler):
    """Handler to update surface tags for specified ways"""

    def __init__(self, surface_map, writer):
        super().__init__()
        self.surface_map = surface_map  # Map of way_id -> surface_value
        self.writer = writer
        self.modified_count = 0
        self.found_count = 0
        self.skipped_count = 0  # Ways that already have surface tag
        self.node_count = 0
        self.way_count = 0
        self.relation_count = 0
        self.last_progress_time = time.time()
        self.progress_interval = 5.0  # Print progress every 5 seconds

    def _print_progress(self, force=False):
        """Print processing progress"""
        current_time = time.time()
        if force or (current_time - self.last_progress_time) >= self.progress_interval:
            print(f"  Processed: {self.node_count:,} nodes, {self.way_count:,} ways, "
                  f"{self.relation_count:,} relations | Modified: {self.modified_count:,} | Skipped: {self.skipped_count:,}",
                  end='\r', flush=True)
            self.last_progress_time = current_time

    def way(self, w):
        """Process each way in the file"""
        self.way_count += 1
        way_id = w.id

        # Check if this way needs to be modified
        if way_id in self.surface_map:
            self.found_count += 1
            new_surface = self.surface_map[way_id]

            # Check if way already has a surface tag
            surface_existed = False
            for tag in w.tags:
                if tag.k == 'surface':
                    surface_existed = True
                    break

            # Only modify if surface tag doesn't exist
            if not surface_existed:
                # Build new tags dictionary with added surface
                new_tags = {}
                for tag in w.tags:
                    new_tags[tag.k] = tag.v
                new_tags['surface'] = new_surface

                # Create modified way
                modified_way = w.replace(tags=new_tags)
                self.writer.add_way(modified_way)
                self.modified_count += 1
            else:
                # Surface already exists, skip modification
                # Get existing surface value
                existing_surface = None
                for tag in w.tags:
                    if tag.k == 'surface':
                        existing_surface = tag.v
                        break

                # print(f"Skipping way https://www.openstreetmap.org/way/{way_id} already has surface='{existing_surface}'")
                self.writer.add_way(w)
                self.skipped_count += 1
        else:
            # Copy way unchanged
            self.writer.add_way(w)

        # Print progress every interval
        if self.way_count % 10000 == 0:
            self._print_progress()

    def node(self, n):
        """Copy nodes unchanged"""
        self.node_count += 1
        self.writer.add_node(n)

        # Print progress every interval
        if self.node_count % 100000 == 0:
            self._print_progress()

    def relation(self, r):
        """Copy relations unchanged"""
        self.relation_count += 1
        self.writer.add_relation(r)

        # Print progress every interval
        if self.relation_count % 1000 == 0:
            self._print_progress()


def load_surface_map(ids_file):
    """
    Load way IDs and surface values from file into a dictionary.
    Format: way_id surface_value (one per line)
    Returns: dict mapping way_id (int) -> surface_value (str)
    """
    surface_map = {}

    try:
        with open(ids_file, 'r') as f:
            line_num = 0
            for line in f:
                line_num += 1
                line = line.strip()

                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue

                # Parse line: way_id surface_value
                parts = line.split(None, 1)  # Split on whitespace, max 2 parts

                if len(parts) != 2:
                    print(f"Warning: Invalid format on line {line_num}: '{line}'")
                    print(f"         Expected format: way_id surface_value")
                    continue

                try:
                    way_id = int(parts[0])
                    surface_value = parts[1].strip()

                    if not surface_value:
                        print(f"Warning: Empty surface value on line {line_num}")
                        continue

                    surface_map[way_id] = surface_value

                except ValueError:
                    print(f"Warning: Invalid way ID on line {line_num}: '{parts[0]}'")
                    continue

        return surface_map

    except FileNotFoundError:
        print(f"Error: File '{ids_file}' not found")
        sys.exit(1)
    except Exception as e:
        print(f"Error reading file '{ids_file}': {e}")
        sys.exit(1)


def format_time(seconds):
    """Format seconds into human-readable time"""
    if seconds < 60:
        return f"{seconds:.2f}s"
    elif seconds < 3600:
        minutes = int(seconds // 60)
        secs = seconds % 60
        return f"{minutes}m {secs:.1f}s"
    else:
        hours = int(seconds // 3600)
        minutes = int((seconds % 3600) // 60)
        secs = seconds % 60
        return f"{hours}h {minutes}m {secs:.0f}s"


def get_file_size_mb(filepath):
    """Get file size in MB"""
    return os.path.getsize(filepath) / (1024 * 1024)


def main():
    # Start total timer
    total_start_time = time.time()

    # Check arguments
    if len(sys.argv) != 3:
        print("Usage: ./modify_osm_ways.py <input.pbf> <ids.txt>")
        print("Example: ./modify_osm_ways.py cyprus-latest.osm.pbf ids.txt")
        print()
        print("Format of ids.txt (each line: way_id surface_value):")
        print("  55678093 paved")
        print("  12345678 asphalt")
        sys.exit(1)

    input_pbf = sys.argv[1]
    ids_file = sys.argv[2]

    # Check if input file exists
    if not os.path.isfile(input_pbf):
        print(f"Error: Input PBF file '{input_pbf}' not found")
        sys.exit(1)

    # Get input file size
    input_size_mb = get_file_size_mb(input_pbf)

    # Generate output filename
    if input_pbf.endswith('.osm.pbf'):
        output_pbf = input_pbf[:-8] + '-modified.osm.pbf'
    elif input_pbf.endswith('.pbf'):
        output_pbf = input_pbf[:-4] + '-modified.osm.pbf'
    else:
        output_pbf = input_pbf + '-modified.osm.pbf'

    # Remove existing output file if it exists
    if os.path.exists(output_pbf):
        print(f"Removing existing output file: {output_pbf}")
        os.remove(output_pbf)
        print()

    print("=" * 70)
    print("OSM Ways Surface Modifier")
    print("=" * 70)
    print()

    # Step 1: Load IDs
    print("Step 1/3: Loading way IDs and surface values from file...")
    step1_start = time.time()
    surface_map = load_surface_map(ids_file)
    step1_time = time.time() - step1_start
    print(f"✓ Loaded {len(surface_map):,} ways to modify (took {format_time(step1_time)})")

    if not surface_map:
        print("No valid entries found in ids file. Nothing to do.")
        sys.exit(0)

    print()

    # Step 2: Process PBF
    print("Step 2/3: Processing PBF file and updating surfaces...")
    print(f"Input:  {input_pbf} ({input_size_mb:.2f} MB)")
    print(f"Output: {output_pbf}")
    print()

    step2_start = time.time()

    try:
        # Create writer for output file
        writer = osmium.SimpleWriter(output_pbf)

        # Create handler with surface map and writer
        handler = SurfaceUpdater(surface_map, writer)

        # Process input file in one pass
        handler.apply_file(input_pbf, locations=True)

        # Print final progress
        handler._print_progress(force=True)
        print()  # New line after progress

        # Close writer
        writer.close()

        step2_time = time.time() - step2_start
        print(f"✓ Processing complete (took {format_time(step2_time)})")
        print()

        # Step 3: Summary
        print("Step 3/3: Summary")
        print("-" * 70)
        step3_start = time.time()

        output_size_mb = get_file_size_mb(output_pbf)
        step3_time = time.time() - step3_start

        print(f"Total elements processed:")
        print(f"  Nodes:     {handler.node_count:>15,}")
        print(f"  Ways:      {handler.way_count:>15,}")
        print(f"  Relations: {handler.relation_count:>15,}")
        print()
        print(f"Modification results:")
        print(f"  Ways modified (added surface):     {handler.modified_count:>10,}")
        print(f"  Ways skipped (already have surface): {handler.skipped_count:>10,}")
        print(f"  Ways found from list:              {handler.found_count:>10,}")
        print(f"  Ways not found in PBF:             {len(surface_map) - handler.found_count:>10,}")

        if handler.found_count < len(surface_map):
            print()
            print("  Note: Some way IDs from the input file were not found in the PBF.")

        print()
        print(f"File sizes:")
        print(f"  Input:  {input_size_mb:>10.2f} MB")
        print(f"  Output: {output_size_mb:>10.2f} MB")
        print()

        # Timing summary
        total_time = time.time() - total_start_time
        print("Timing:")
        print(f"  Step 1 (Load IDs):     {format_time(step1_time):>10}")
        print(f"  Step 2 (Process PBF):  {format_time(step2_time):>10}")
        print(f"  Step 3 (Summary):      {format_time(step3_time):>10}")
        print(f"  Total time:            {format_time(total_time):>10}")

        # Calculate throughput
        if step2_time > 0:
            throughput_mb_s = input_size_mb / step2_time
            print(f"  Throughput:            {throughput_mb_s:>10.2f} MB/s")

        print()
        print("=" * 70)
        print(f"✓ Success! Output file: {output_pbf}")
        print("=" * 70)
        print()
        print("To verify the changes, run:")
        print(f"  osmium getid {output_pbf} w<WAY_ID> -f osm | grep '<tag'")

    except Exception as e:
        print(f"\n✗ Error processing PBF file: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
