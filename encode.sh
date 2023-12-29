#!/bin/bash

###################################################################
# input parameters
# $1: file match pattern, support wildcard, dir name
# $2: overall bitrate of encoded video, unit is kb/s
# $3: start time points of source video
# $4: format of encoded video

pattern=*
start_point=
default_bitrate=""
custom_format=""

if [ -n "$1" ]; then
	default_bitrate=$1
fi

if [ -n "$2" ]; then
	pattern=$2
fi
if [ -d "$pattern" ]; then
	pattern="$pattern/*"
fi

if [ -n "$3" ]; then
	custom_format=$3
fi

if [ -n "$4" ]; then
	start_point=$4
fi


###################################################################
# config parameters

default_format="mkv"               #.mp4=>.mp4, .mkv=>.mkv, other=>default_format
convert_dir=converted              # converted dir where the encoded video to put
finish_dir=finished                # finished dir where the source video to put when encoded successfully
temp_dir=$HOME/convert_temp        # where to save info files, like log
log_dir="$temp_dir/log"            # where to save encoding log
converting_prefix="==converting==" # filename prefix for converting file
# for RTX4090, support max 5 procs
process_num=${ENCODE_PROC:-2}      # number of encoding processes
flags_file="flags.txt"

###################################################################
# ffmpeg parameters

FFMPEG="ffmpeg"
MAP_FLAGS="-map 0"
COMMON_FLAGS="-max_muxing_queue_size 4096 -c:s copy -c:d copy "
HWACCEL="-hwaccel cuvid "
HWENCODE="-c:v hevc_nvenc -preset fast -b "
CPUENCODE="-c:v libx265 -preset fast -b "
AUDIO_COPY="-c:a copy "

# EXTERNAL_MAP_FLAGS is used to change stream mapping and add filters,
# using "export EXTERNAL_MAP_FLAGS=xxx" to set value, for example:
# to save video and audio, and using crop,delogo filters
#     EXTERNAL_MAP_FLAGS="-map 0:v -map 0:a -vf crop=920:720:173:7,delogo=x=794:y=38:w=74:h=58"
# to save video, audio and subtitle
#     EXTERNAL_MAP_FLAGS="-map 0:v -map 0:a -map 0:s

####################################################################
source `dirname "${BASH_SOURCE[0]}"`/common_utils.sh
function auto_map(){
	local name=$1
	local sname=${name%.*}
	local map_str="-map 0:V -map 0:a "
	if [ -e "${sname}.ass" ]; then
		map_str="-i '${sname}.ass' $map_str -map 1 "
	fi
	if [ -e "${sname}.srt" ]; then
		map_str="-i '${sname}.srt' $map_str -map 1 "
	fi
	if [ -e "${sname}.ssa" ]; then
		map_str="-i '${sname}.ssa' $map_str -map 1 "
	fi
	map_str="$map_str -map 0:s?" # -map 0:d? -map 0:t?
	echo "$map_str"
}

function try_ffmpeg(){
	local ret=$1
	local flags
	shift 1
	flags=$*
	local before_flags=${flags%%\@*}
	flags=${flags#*\@}
	local src_name=${flags%%\@*}
	flags=${flags#*\@}
	local middle_flags=${flags%%\@*}
	flags=${flags#*\@}
	local dst_name=${flags%%\@*}
	local after_flags=${flags#*\@}

	local start_flags=""
	if [ -n "$start_point" ]; then
		start_flags="-ss $start_point"
	fi
	before_flags=`echo $before_flags | sed -e 's/ +/ /g'`
	middle_flags=`echo $middle_flags | sed -e 's/ +/ /g'`
	local extra_flags=`get_extra_flags "$src_name"`
	after_flags=`echo $after_flags | sed -e 's/ +/ /g'`
	if [ $ret -ne 0 ]; then
		if [ -e "$converting_name" ]; then
			rm "$converting_name"
		fi
		command="$FFMPEG $start_flags $before_flags \"$src_name\" $middle_flags $extra_flags \"$dst_name\" $after_flags"
		echo "==>running \"$command\""
		echo $command | bash
		#$FFMPEG $before_flags "$src_name" $middle_flags $extra_flags "$dst_name" $after_flags
		ret=$?
		if video_is_invalid "$converting_name"; then
			ret=1
		fi
	fi
	return $ret
}
function encode_func() {
	local target=$1
	local current=-1
	local finish_count=0
	local ignore_count=0
	local fail_count=0
	local base_bitrate
	local src_name
	local src_dir
	local src_bitrate_value
	local src_bitrate
	local src_finish_dir
	local dst_dir
	local dst_name
	local dst_format
	local dst_bitrate_value
	local dst_bitrate
	local bitrate_unit
	local converting_name
	local height
	local map_flags
	local REAL_COMMON_FLAGS
	if [ -z "$target" ]; then
		target=0
	fi
	for ((i=0; i<$file_count;i++)) do
		name=${file_list[$i]}
		current=$(($current+1))
		tag=$((current%process_num))
		if [ $tag -ne $target ]; then
			continue;
		fi
		echo "target=$target"
		echo "----->process=$target finished=$finish_count failed=$fail_count ignored=$ignore_count converting=$name"
		src_dir=`dirname "$name"`
		src_name=`basename "$name"`
		dst_format=""
		if [ -n "$custom_format" ]; then
			dst_format=$custom_format
		fi
		if [ -z "$dst_format" ]; then
			src_format=${name##*.}
			if [ "$src_format" == "mp4" -o  "$src_format" == "MP4" ]; then
				dst_format="mp4"
			elif [ "$src_format" == "mkv" -o  "$src_format" == "MKV" ]; then
				dst_format="mkv"
			else
				dst_format=$default_format
			fi
		fi
		dst_dir="$src_dir/$convert_dir"
		dst_name="${src_name%.*}.$dst_format"
		converting_name="${converting_prefix}${dst_name}"
		dst_name="$dst_dir/$dst_name"
		converting_name="$src_dir/${converting_name}"
		line=`ffprobe -i "$name" 2>&1 | grep "Duration.*bitrate"`
		if [ -z "$line" ]; then
			echo "<$name> is not a valid video file!"
			((ignore_count++))
			continue;
		fi
		duration=${line%%,*}
		duration=${duration##*: }
		if [ "$duration" == "N/A" ]; then
			echo "<$name> is not a valid video file!"
			((ignore_count++))
			continue
		fi
		bitrate=${line##*bitrate: }
		src_bitrate_value=${bitrate% *}
		bitrate_unit=${bitrate#* }
		bitrate_unit=${bitrate_unit%b*}
		dst_bitrate_value=$(($src_bitrate_value*3/5))
		line=`ffprobe -i "$name" 2>&1 | grep "Stream #.*Video:" | grep -v mjpeg | grep -v png`
		src_encoding_format=${line#*Video: }
		src_encoding_format=${src_encoding_format%% *}
		pix_format=${line#*yuv}
		pix_format=${pix_format%%(*}
		pix_format="-pix_fmt yuv${pix_format%%,*}"
		resolution=`echo $line | grep -P '(\d{3,})x(\d{3,})' -o`
		echo $resolution
		height=${resolution#*x}
		base_bitrate=2000
		# for movie
		if [ $height -ge 2160 ]; then
			base_bitrate=4000
		elif [ $height -ge 1080 ]; then
			base_bitrate=2000
		elif [ $height -ge 720 ]; then
			base_bitrate=1500
		elif [ $height -ge 576 ]; then
			base_bitrate=800
		elif [ $height -ge 480 ]; then
			base_bitrate=700
		else
			base_bitrate=600
		fi
		if [ $dst_bitrate_value -gt $base_bitrate ]; then
			dst_bitrate_value=$base_bitrate
		fi
		if [ -n "$default_bitrate" ]; then
			dst_bitrate_value=$default_bitrate
		fi

		if [ "$src_encoding_format" == "hevc" -o "$src_encoding_format" == "HEVC" ]; then
			if [ $dst_bitrate_value -ge $src_bitrate_value ]; then 
				echo "<$name> is already encoded as hevc, bitrate $src_bitrate_value kb/s"
				((ignore_count++))
				continue
			fi
		fi
		if [[ $line =~ .*bt2020.* ]]; then
			echo "<$name> is a HDR video, encode.sh not support yet."
			((ignore_count++))
			continue
		fi
		echo "==>begin encoding: $name"
		echo "src_name=<$name>, dst_name=<$dst_name>"
		echo "src_bitrate=$src_bitrate_value, dst_bitrate=$dst_bitrate_value"

		REAL_COMMON_FLAGS=""
		if [ -n "$EXTERNAL_MAP_FLAGS" ]; then
			REAL_COMMON_FLAGS="$EXTERNAL_MAP_FLAGS $COMMON_FLAGS"
		else
			map_flags=`auto_map "$name"`
			REAL_COMMON_FLAGS="$map_flags $COMMON_FLAGS"
		fi

		dbr=$dst_bitrate_value$bitrate_unit
		ret=1
		try_ffmpeg $ret "$HWACCEL -i @$name@ $REAL_COMMON_FLAGS             $HWENCODE  $dbr $pix_format @$converting_name@"; ret=$?
		try_ffmpeg $ret "         -i @$name@ $REAL_COMMON_FLAGS             $HWENCODE  $dbr $pix_format @$converting_name@"; ret=$?
		#try_ffmpeg $ret "         -i @$name@ $REAL_COMMON_FLAGS             $CPUENCODE $dbr $pix_format @$converting_name@"; ret=$?
		try_ffmpeg $ret "$HWACCEL -i @$name@ $REAL_COMMON_FLAGS $AUDIO_COPY $HWENCODE  $dbr $pix_format @$converting_name@"; ret=$?
		try_ffmpeg $ret "         -i @$name@ $REAL_COMMON_FLAGS $AUDIO_COPY $HWENCODE  $dbr $pix_format @$converting_name@"; ret=$?
		#try_ffmpeg $ret "         -i @$name@ $REAL_COMMON_FLAGS $AUDIO_COPY $CPUENCODE $dbr $pix_format @$converting_name@"; ret=$?

		if [ $ret -ne 0 ]; then
			echo "<$name> cannot be converted!"
			((fail_count++))
			if [ -e "$converting_name" ]; then
				rm "$converting_name"
			fi
		fi

		echo "==>end encoding: $name"
		if [ $ret -ne 0 ]; then
			continue;
		fi
		src_finish_dir="$src_dir/$finish_dir"
		if [ ! -e "$src_finish_dir" ]; then
			mkdir -p "$src_finish_dir"
		fi
		if [ ! -e "$dst_dir" ]; then
			mkdir -p "$dst_dir"
		fi
		mv "$name" "$src_finish_dir/$src_name"
		mv "$converting_name" "$dst_name"
		((finish_count++))
	done
	echo "----->process=$target finished=$finish_count failed=$fail_count ignored=$ignore_count converting="
}


file_list=()
file_count=0
for file in $pattern;
do
	if [ ! -f "$file" ]; then
		continue;
	fi
	if [ "${file##*.}" == "ass" ]; then
		continue
	fi
	if [ "${file##*.}" == "srt" ]; then
		continue
	fi
	if [ "${file##*.}" == "ssa" ]; then
		continue
	fi
	if [ "${file##*.}" == "txt" ]; then
		continue
	fi
	bname=`basename "$file"`
	new_name=${bname/$converting_prefix/}
	if [ "$bname" == "$new_name" ]; then
		file_list[$file_count]="$file"
		((file_count++))
	fi
done
for ((i=0; i<$file_count;i++)) do
	name=${file_list[$i]}
	echo "$i '$name'"
done
if [ -e "$log_dir" ]; then
	rm -r $log_dir
fi
mkdir -p "$log_dir"
pcount=0
if [ $file_count -eq 0 ]; then
	exit
fi
if [ $file_count -eq 1 ]; then
	process_num=1
fi
for t in `seq $process_num`; do
	logfile="$log_dir/$pcount.log"
	target=$pcount
	{
		encode_func $target &>$logfile
	}&
	((pcount++))
done

running_count=$process_num
while [ $running_count -ne 0 ]; do
	sleep 2
	total_finished=0
	total_ignored=0
	total_failed=0
	unset convertings
	convertings[0]=""
	running_count=0
	for f in "$log_dir"/*.log; do
		line=`grep "finished=.*failed" "$f" | tail -n 1`
		if [ -z "$line" ]; then
			continue;
		fi
		finished=${line##*finished=}
		finished=${finished%% *}
		failed=${line##*failed=}
		failed=${failed%% *}
		ignored=${line##*ignored=}
		ignored=${ignored%% *}
		converting=${line##*converting=}
		total_finished=$((total_finished+finished))
		total_failed=$((total_failed+failed))
		total_ignored=$((total_ignored+ignored))
		if [ -n "$converting" ]; then
			line=`tail -n 1 "$f"`
			if [[ "$line" =~ frame=.* ]]; then
				process="${line##*time=}"
				process="${process%x*}"	
				process="${process/bitrate=/}"
				process="${process%%bits*}b/s x${process##*speed=}"
				converting="$converting<$process>"
			fi
			convertings[$running_count]="$converting"
			((running_count++))
		fi

	done

	date_str=`date +%H:%M:%S`
	if [ "$running_count" != "$last_run_process" -o "$last_total_failed" != "$total_failed" -o "$last_total_finished" != "$total_finished" -o "$last_total_ignored" != "$total_ignored" ]; then
	    echo ""
		echo  "$date_str: run_process: $running_count, total_files: $file_count, finished: $total_finished, failed: $total_failed ignored: $total_ignored"
	fi
	if [ "${#convertings[@]}" -gt 0 ]; then
		echo -e "\r$date_str: converting: (${convertings[@]})\c"
	fi
	last_total_finished=$total_finished
	last_total_ignored=$total_ignored
	last_total_failed=$total_failed
	last_run_process=$running_count
done
echo ""
