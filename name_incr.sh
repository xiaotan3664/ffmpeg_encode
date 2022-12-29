#!/bin/bash

delta=$2
if [ -z "$delta" ]; then
	delta=0
fi
pattern=$1
if [ -z "$pattern" ]; then
	pattern="*"
fi

prefix=$3
cmd="ls -r $pattern"
if [ "$delta" -lt 0 ]; then
cmd="ls $pattern"
fi

for name in `$cmd`; do
	extname=${name##*.}
	oldname=${name%.*}
	len=${#oldname}
	val=${oldname%%[1-9]*}
	zerolen=${#val}
	val=${oldname:$zerolen}
	if [ -z "$val" ]; then
		val=0;
	fi
	newname="00000000000000"$((val+delta))
	newlen=${#newname}
	newstart=$((newlen-len))
	newname=${prefix}${newname:${newstart}:${len}}.${extname}
	if [ ! -e $newname ]; then
		echo "$name->$newname"
		mv $name $newname
	else
		echo "cannot rename $name->$newname"
	fi
done
