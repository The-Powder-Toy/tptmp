#!/bin/bash

set -euo pipefail
IFS=$'\t\n'

RELEASE_NAME="$(echo "$GITHUB_REF_NAME" | cut -d "/" -f 3-)"
gh release create --verify-tag --title $RELEASE_NAME $GITHUB_REF_NAME
