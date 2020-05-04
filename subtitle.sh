#!/bin/bash

function try_video(){
	local name=$1
	local ext=$2
	video_name="${name%.*}.$ext"
	if [ -e "$video_name" ]; then
		ffmpeg -i "$video_name" -i "$name" -map 0:v -map 0:a -map 0:d? -map 1:s -c copy "s_$video_name"
	fi
}
function try_subtitle(){
	local ext=$1
	for name in *.$ext; do
		if [ ! -e "$name" ]; then
			continue;
		fi
		try_video "$name" "mkv"
		try_video "$name" "mp4"
	done
}

try_subtitle ass
try_subtitle srt
