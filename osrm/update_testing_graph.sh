set -x

apt install osmium-tool

# build_merged_graph.sh --profile road|gravel publishes to ~/disk/share/osrm_merged_<profile>;
# app-testing.properties reads them from ~/data/osrm_merged_<profile>/merged.
for BUILD_DIR in osrm_merged_road osrm_merged_gravel; do
    rm -rf ~/data/${BUILD_DIR}
    cp -r ~/disk/share/${BUILD_DIR} ~/data/${BUILD_DIR}
done

cd ~/data/osrm_merged_road

sudo systemctl restart osrm.service
sudo systemctl restart autoroute.service
#~/disk/osrm-backend/build/osrm-routed --algorithm ch --mmap on merged.osrm -p 8005
~/disk/osrm-backend/build/osrm-routed --algorithm mld --mmap on merged.osrm -p 8005
