set -ex

#./download_heyGIT.sh
#./merge_json_files.sh ~/disk/share/heigit_road_surface_data

cd ~/disk
rm heygit_ids.txt
echo "start grep surface from all_roads"
grep "\"surface\": null" ~/disk/share/heigit_road_surface_data/all_roads.geojson | grep "\"combined_surface_osm_priority\": \"paved\"" | grep -Eo '"osm_id": [0-9]+' | awk '{print $2 " paved"}' | sort -u > heygit_ids.txt
echo "finish grep surface from all_roads"