#!/bin/bash

set -euo pipefail
IFS=$'\t\n'

if [[ -d dist ]]; then
	rm -r dist
fi
mkdir dist
cp -r tptmp modulepack.conf dist/
cd dist
config_lua="$(grep -rn tptmp -e "local versionstr" | cut -d ":" -f 1)"
real_version="$(echo "$1" | cut -d "/" -f 3-)"
sed -i "$config_lua" -Ee 's/"v2\.[^"]+"/"'"$real_version"'"/'
git submodule update --init
luajit ../TPT-Script-Manager/modulepack.lua modulepack.conf > client.dist.lua
