#!/bin/bash
prefix="*[0-9]E"
suffix=".*"
default_ext=
if [ -n "$1" ]; then
	prefix=$1
fi
if [ -n "$2" ]; then
	suffix=$2
fi
if [ -n "$3" ]; then
	default_ext=$3
fi
for name in *; do
	ext=".${name##*.}"
	if [ -n "$default_ext" ]; then
		ext=".$default_ext"
	fi
	if [ -d "$name" ]; then
		ext=""
	fi
	new_name="${name##$prefix}"
	new_name="${new_name%%$suffix}${ext}"
	if [ ! -e "$new_name" ]; then
		echo "rename '$name'->'$new_name'"
		mv "$name" "$new_name"
	fi
done
