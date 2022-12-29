#!/bin/bash

index=1
namelen=3
for name in `ls -t -r *`; do
	extname=${name##*.}
	newname="000000000000"$index
	index=$((index+1))
	newlen=${#newname}
	start=$((newlen-namelen))
	newname=${newname:$start}.${extname}
	if [ ! -e $newname ]; then
		echo "$name->$newname"
		mv $name $newname
	fi
done
