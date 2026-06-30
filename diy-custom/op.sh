#!/bin/sh
wget https://ghproxy.3284123.xyz/https://raw.githubusercontent.com/vernesong/OpenClash/core/dev/smart/clash-linux-arm64.tar.gz -O /tmp/ca_op.tar.gz
cd /tmp
7z x ca_op.tar.gz
7z x ca_op.tar
chmod 777 clash
mv clash /etc/openclash/core/clash_meta
rm ca_op.*
echo "Done"
exit 0
