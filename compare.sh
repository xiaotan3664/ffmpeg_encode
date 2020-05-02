#!/bin/bash

src_file=$1
dst_file=$2
start_point=$3
height=540
width=960
screen_height=$((height*2))
screen_width=$((width*2))
resolution=${width}x${height}
screen_resolution=${screen_width}x${screen_height}
-
#ffplay -re -i "$src_file" -re -i "$dst_file" -filter_complex "nullsrc=size=$screen_resolution [base]; [0:v] setpts=PTS-STARTPTS,scale=$resolution [left];[1:v]setpts=PTS-STARTPTS, scale=$resolution [right]; [base][left] overlay=shortest=1[tmp1];[tmp1][right]overlay=shortest=1:x=$width [final]" #-c:v libx265

ffplay -i "$src_file" -ss $start_point&
ffplay -i "$dst_file" -ss $start_point
