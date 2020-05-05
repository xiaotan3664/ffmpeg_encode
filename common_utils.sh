#!/bin/bash

function get_extra_flags(){
	local flags_file="flags.txt"
	local name=$1
	local flag_file_path=`dirname "$name"`/$flags_file
	if [ ! -e "$flag_file_path" ]; then
		return
	fi
	local name_tag=`basename "$name"`
	name_tag="${name_tag%.*}"
	local line=`cat "$flag_file_path" | grep "^${name_tag}:"`
	line=${line#*:}
	echo $line
}

function video_is_invalid(){
	if [ ! -e "$1" ]; then
		return 0
	fi
	line=`ffprobe -i "$1" 2>&1 | grep "Duration.*bitrate"`
	if [ -z "$line" ]; then
		echo "<$converting_name> is not valid"
		return 0
	else 
		duration=${line%%,*}
		duration=${duration##*: }
		if [ "$duration" == "N/A" ]; then
			echo "<$converting_name> is not valid"
			return 0
		fi
	fi
	return 1
}

function trim_str(){
	local var=$1
	var=${var#"${var%%[![:space:]]*}"}
	var=${var%"${var##*[![:space:]]}"}
	echo "$var"
}
