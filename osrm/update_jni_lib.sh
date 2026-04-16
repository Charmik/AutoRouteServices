set -ex

cd ~/disk/AutoRoute
rm -rf target
./build_osrm_jni.sh
rm -rf ~/data/AutoRoute/target_old
mv ~/data/AutoRoute/target ~/data/AutoRoute/target_old
mkdir -p ~/data/AutoRoute/target/lib
cp target/lib/libosrmjni.so ~/data/AutoRoute/target/lib