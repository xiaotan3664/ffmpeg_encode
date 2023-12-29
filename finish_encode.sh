#!/bin/bash

CONVERTED_DIR=${1:-converted}
FINISHED_DIR=${2:-finished}
for i in `find -name $CONVERTED_DIR`; do
  for f in $i/*; do
    filename=`basename $f`
    if [ -e "$i/../$filename" ]; then
      echo "$i/../$filename exists, cannot override."
      continue
    fi
    mv -vn "$f" "$i/../"
  done
  finished_dir=`realpath $i/../$FINISHED_DIR`
  rmdir -v "$i"
  if [ "$?" -ne 0 ]; then
    continue
  fi
  if [ -d "$finished_dir" ]; then
    rm -vr "$finished_dir"
  fi
done
