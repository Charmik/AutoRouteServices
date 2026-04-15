set -x

#systemd-run --user --scope -p MemoryMax=30G ~/disk/osrm-backend/build/osrm-routed --mmap --algorithm mld planet-latest.osrm -p 8003
#systemd-run --user --scope -p MemoryMax=200G ~/disk/osrm-backend/build/osrm-routed --algorithm mld planet-latest.osrm -p 8003

sudo swapoff -a
python3 validate_graph.py capitals_test.csv
python3 validate_graph.py capitals_full.csv
python3 validate_graph.py worldcities.csv
sudo swapon swap