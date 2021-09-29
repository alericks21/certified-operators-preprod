#!/usr/bin/env bash

set -euo pipefail


## Functions

usage() {
  echo -n "$(basename "$0") [OPTION]

Fixup cr filenames

 Options:
  -d, --directory        [REQUIRED] Directory of cr's
  -h, --help             Display this help and exit

"
exit 0
}

## MAIN

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -d|--directory)
    DIRECTORY="$2"
    shift 2
    ;;
    -h|--help)
    usage
    shift
    ;;
    --) # end argument parsing
    shift
    break
    ;;
    --*=|-*) # unsupported flags
    echo "Unsupported flag $1"
    exit -1
    ;;
    *)
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
#set -- "${POSITIONAL[@]}" # restore positional parameters

echo "dir is --> $DIRECTORY"

for file in `cd $DIRECTORY; ls`; do 
    if [[ $file == *"_cr.yaml"* ]]; then
        echo "file already renamed $file"   
    else
        newf=$(echo ${file} | sed 's|.yaml|_cr.yaml|g')
        mv $DIRECTORY/$file $DIRECTORY/$newf    
    fi 
done