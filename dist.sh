#!/bin/bash

set -Eeuo pipefail
IFS=$'\t\n'

if [[ -d dist ]]; then
	rm -r dist
fi
mkdir dist
cp -r tptmp modulepack.conf dist/
cd dist
config_lua="$(grep -rn tptmp -e "local versionstr" | cut -d ":" -f 1)"
real_version="$(echo "$1" | cut -d "/" -f 3-)"
sed -i tptmp/client/config.lua -Ee 's/"v2\.[^"]+"/"'"$real_version"'"/'
curl -fsS https://raw.githubusercontent.com/The-Powder-Toy/TPT-Script-Manager/refs/heads/master/modulepack.lua > modulepack.lua
luajit modulepack.lua modulepack.conf > client.dist.lua
