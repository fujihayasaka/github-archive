#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Print usage message for this script.
help() {
   echo "Finds TypeScript files that don't have a corresponding test file."
   echo
   echo "Usage: script/find-untested-package-files.sh [package path]"
   echo
}

packageDir=$1

if [ -z "$packageDir" ]; then # no package directory path was provided
  help
  exit 1
fi

if [[ ! -d "$packageDir" ]]; then
  echo -e "${RED}Error: directory '$packageDir' does not exist.${NC}"
  exit 1
fi

echo -e "${GREEN}Looking for untested files in $packageDir...${NC}"

packageFiles=$(find "$packageDir" -type f \
  -name \*.ts \
  -o -name \*.tsx)
untestedFiles=()

for path in $packageFiles; do
  if [[ ! -f "$path" ]]; then # not a file
    continue
  fi

  if [[ "$path" == *.test.ts || "$path" == *.test.tsx ]]; then # test file
    continue
  fi

  if [[ "$path" == *.d.ts ]]; then # type definition file
    continue
  fi

  if [[ "$path" == */__tests__/* ]]; then # test utility file
    continue
  fi

  extension="${path##*.}"
  dir="${path%/*}"
  baseName="${path##*/}"

  if [[ "$extension" == "ts" ]]; then
    expectedTestFile="$dir/__tests__/${baseName%.*}.test.ts"
    alternateTestFile="$dir/__browser-tests__/${baseName%.*}.test.ts"
  elif [[ "$extension" == "tsx" ]]; then
    expectedTestFile="$dir/__tests__/${baseName%.*}.test.tsx"
    alternateTestFile="$dir/__browser-tests__/${baseName%.*}.test.tsx"
  else
    continue
  fi

  if [[ -f "$alternateTestFile" || -f "$expectedTestFile" ]]; then
    continue
  fi

  echo -e "${RED}Expected either ${expectedTestFile} or ${alternateTestFile} to exist.${NC}"
  untestedFiles+=("$path")
done

for untestedFile in "${untestedFiles[@]}"; do
  echo "- [ ] "'`'"${untestedFile}"'`'
done

if [ ${#untestedFiles[@]} -eq 0 ]; then
  echo -e "${GREEN}All files in $packageDir are tested.${NC}"
  exit 0
fi
