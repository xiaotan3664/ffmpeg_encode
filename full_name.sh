#!/bin/bash
level=${1:-1}
prefix_inner="${2:-S0}"
prefix_current="E"

current_dir="$PWD"
if [ $level  -eq 2 ]; then
	current_season=$(basename "$current_dir")
	current_season=${current_season%.*}
	prefix=$(basename `cd $current_dir/.. && pwd`).$prefix_inner${current_season}$prefix_current
else
	prefix_current="EP"
	prefix=$(basename "$current_dir").$prefix_current
fi

revert_name=`mktemp`
for i in *; do
	fullname="${prefix}${i}"
	if [ -e $fullname ]; then
		echo "$fullname exists, ignored"
		continue
	fi

	echo "'$i'->'$fullname'"
	mv "$i" "$fullname"
	echo "mv '$fullname' '$i'" >> "$revert_name"
done
chmod +x $revert_name

echo "you can run '$revert_name' to revert"
