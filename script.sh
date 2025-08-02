#!/usr/bin/env bash

set -e

VERSION="$1"

DOWNLOAD_PATH="./tarball"
TARBALL_URL="https://github-enterprise.s3.amazonaws.com/ami/updates/github-enterprise-ami-$VERSION.pkg"

wget "$TARBALL_URL" -O "$DOWNLOAD_PATH"

cat_script() {
    sed '/^exit$/q' "$DOWNLOAD_PATH"
}

cat_data() {
    sed '0,/^exit$/d' "$DOWNLOAD_PATH"
}

tar_args(){
  if [ -z "${TAR_ARGS:-}" ] ; then
    if cat_data | file - | grep -q "XZ compressed data"; then
      TAR_ARGS="-xJf"
    else
      TAR_ARGS="-xf"
    fi
  fi
  echo "$TAR_ARGS"
}

cat_archive() {
    eval $(cat_script | grep -m 1 -E 'cat_data \| head --bytes=[0-9]+$')
}

cat_archive | pv | tar --overwrite -C "." $(tar_args) - ./data/github/current

echo "decoding files"

ruby decode.rb

export GIT_AUTHOR_DATE=2025-01-01T00:00:00Z
export GIT_COMMITTER_DATE=2025-01-01T00:00:00Z
export GIT_AUTHOR_EMAIL=null
export GIT_AUTHOR_NAME=null
export GIT_COMMITTER_NAME=null
export GIT_COMMITTER_EMAIL=null

git add .
git commit -m "$VERSION"
git push -u origin @
