#cd ~/disk/osrm-backend/build
#./osrm-datastore --remove-locks
#./osrm-datastore --spring-clean
#./osrm-datastore --list
#./osrm-datastore --dataset-name=planet-latest ~/data/osrm/planet-latest.osrm
#./osrm-datastore --list
#./osrm-routed --algorithm mld --shared-memory on --dataset-name planet-latest


cd ~/disk/osrm-backend/build
./osrm-datastore --remove-locks
./osrm-datastore --spring-clean
./osrm-datastore --list
ipcs -m
free -h
./osrm-datastore --dataset-name=part1 /home/charm/data/osrm/part1/planet-part1-modified --disable-feature-dataset ROUTE_STEPS
./osrm-datastore --dataset-name=part2 /home/charm/data/osrm/part2/planet-part2-modified --disable-feature-dataset ROUTE_STEPS
./osrm-datastore --list
./osrm-routed --algorithm ch --shared-memory on --dataset-name part1
./osrm-routed --algorithm ch --shared-memory on --dataset-name part2


# CLEAR SHARED MEMORY
#ipcs -m #check shmid ids here
#ipcrm -m 15
#ipcrm -m 16


# check shared-memory files
#JAVA_PID=$(pgrep -f "AutoRoute.jar" | head -1)
#cat /proc/$JAVA_PID/maps | grep -i "shmem\|osrm"