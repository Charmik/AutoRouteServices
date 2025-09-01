cd ~/disk/osrm-backend/build
./osrm-datastore --remove-locks
./osrm-datastore --spring-clean
./osrm-datastore --list
./osrm-datastore --dataset-name=planet-latest ~/data/osrm/planet-latest.osrm
./osrm-datastore --list
./osrm-routed --algorithm mld --shared-memory on --dataset-name planet-latest