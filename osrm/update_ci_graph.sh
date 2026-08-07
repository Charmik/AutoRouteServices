set -x

# Copy both profile graphs built by build_merged_graph.sh (osrm_merged_road / osrm_merged_gravel).
for PROFILE in road gravel; do
    BUILD_DIR="osrm_merged_${PROFILE}"
    rm -rf ~/data/osrm_for_CI_${PROFILE}
    cp -r ~/disk/share/${BUILD_DIR} ~/data/osrm_for_CI_${PROFILE}
done

#cd ~/data/osrm_for_CI_gravel
#~/disk/osrm-backend/build/osrm-routed --algorithm ch --mmap on merged.osrm -p 8006 &

#cd ~/data/osrm_for_CI_road
#~/disk/osrm-backend/build/osrm-routed --algorithm ch --mmap on merged.osrm -p 8005
