#!/usr/bin/env bash

set -e

VERSION="$1"

DOWNLOAD_PATH="./tarball"
TARBALL_URL="https://github-enterprise.s3.amazonaws.com/ami/updates/github-enterprise-ami-$VERSION.pkg"

wget "$TARBALL_URL" -O "$DOWNLOAD_PATH"

cat_script() {
    LC_ALL=C sed '/^exit$/q' "$DOWNLOAD_PATH"
}

cat_data() {
    LC_ALL=C sed '1,/^exit$/d' "$DOWNLOAD_PATH"
}

tar_args(){
  if [ -z "${TAR_ARGS:-}" ] ; then
    if cat_data | head -c 1024 | file - | grep -q "XZ compressed data"; then
      TAR_ARGS="-xJf"
    else
      TAR_ARGS="-xf"
    fi
  fi
  echo "$TAR_ARGS"
}

cat_archive() {
    local bytes
    bytes=$(cat_script | grep -m 1 -E 'cat_data \| head --bytes="?[0-9]+"?$' | tr -dc '0-9')
    cat_data | head -c "$bytes"
}

cat_archive | tar -v -C "." $(tar_args) - ./data/github/current

echo "decoding files"

ruby decode.rb

export TZ=UTC
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
export GIT_AUTHOR_EMAIL="null"
export GIT_AUTHOR_NAME="null"
export GIT_COMMITTER_NAME="null"
export GIT_COMMITTER_EMAIL="null"

git add .
git -c commit.gpgsign=false commit --no-gpg-sign -m "$VERSION"
git push --force-with-lease -u origin @
