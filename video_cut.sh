#!/bin/bash
source `dirname "${BASH_SOURCE[0]}"`/common_utils.sh

cut_dir="cut"
pattern="*"
if [ -n "$1" ]; then
	pattern=$1
fi
for name in $pattern; do
	if [ ! -e "$name" ]; then
		continue
	fi
	cut_flags=`get_extra_flags "$name"`
	dst_dir="`dirname $name`/$cut_dir"
	dst_name="$dst_dir/`basename $name`"
	if [ -z "$cut_flags" ]; then
		continue
	fi
	start_flags=""
	end_flags=""
	tmp_str="${cut_flags#*-ss}"
	if [ "$tmp_str" != "$cut_flags" ]; then
		start_point=`trim_str "${tmp_str}"`
		start_point=${start_point%% *}
		start_flags="-ss $start_point"
	fi

	tmp_str="${cut_flags#*-to}"
	if [ "$tmp_str" != "$cut_flags" ]; then
		end_point=`trim_str "${tmp_str}"`
		end_point=${end_point%% *}
		end_flags="-to $end_point"
	fi
	if [ -n "$start_flags" -o -n "$end_flags" ]; then
		if [ ! -e "$dst_dir" ]; then
			mkdir -p "$dst_dir"
		fi
		echo "ffmpeg $start_flags -i $name -map 0 $end_flags -c copy -y $dst_name"
		ffmpeg -i "$name" -map 0 $start_flags -c copy -avoid_negative_ts 1 $end_flags -y "$dst_name"
	fi

done
