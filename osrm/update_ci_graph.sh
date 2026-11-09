set -x

# Copy the profile graphs built by build_merged_graph.sh (osrm_merged_road / _gravel / _walk); walk is skipped until it
# has been built, because it is not hosted yet.
for PROFILE in road gravel walk; do
    BUILD_DIR="osrm_merged_${PROFILE}"
    if [ "$PROFILE" = "walk" ] && [ ! -d ~/disk/share/${BUILD_DIR} ]; then echo "skip ${BUILD_DIR}: not built"; continue; fi
    rm -rf ~/data/osrm_for_CI_${PROFILE}
    cp -r ~/disk/share/${BUILD_DIR} ~/data/osrm_for_CI_${PROFILE}
done

#cd ~/data/osrm_for_CI_gravel
#~/disk/osrm-backend/build/osrm-routed --algorithm ch --mmap on merged.osrm -p 8006 &

#cd ~/data/osrm_for_CI_road
#~/disk/osrm-backend/build/osrm-routed --algorithm ch --mmap on merged.osrm -p 8005
