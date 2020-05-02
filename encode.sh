#!/bin/bash

###################################################################
# input parameters
# $1: file match pattern, support wildcard, dir name
# $2: overall bitrate of encoded video, unit is kb/s
# $3: start time points of source video
# $4: format of encoded video

pattern=*
start_point=0
default_bitrate=""
custom_format=""
if [ -n "$1" ]; then
	pattern=$1
fi
if [ -d "$pattern" ]; then
	pattern="$pattern/*"
fi

if [ -n "$2" ]; then
	default_bitrate=$2
fi

if [ -n "$3" ]; then
	start_point=$3
fi

if [ -n "$4" ]; then
	custom_format=$4
fi

###################################################################
# config parameters

default_format="mp4"               #.mp4=>.mp4, .mkv=>.mkv, other=>default_format
convert_dir=converted              # converted dir where the encoded video to put
finish_dir=finished                # finished dir where the source video to put when encoded successfully
temp_dir=$HOME/convert_temp        # where to save info files, like log
log_dir="$temp_dir/log"            # where to save encoding log
converting_prefix="==converting==" # filename prefix for converting file
process_num=2                      # number of encoding processes

###################################################################
# ffmpeg parameters

FFMPEG="ffmpeg -ss $start_point "
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

if [ -z "$EXTERNAL_MAP_FLAGS" ]; then
	COMMON_FLAGS="$MAP_FLAGS $COMMON_FLAGS"
else
	COMMON_FLAGS="$EXTERNAL_MAP_FLAGS $COMMON_FLAGS"
fi

####################################################################
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

	before_flags=`echo $before_flags | sed -e 's/ +/ /g'`
	middle_flags=`echo $middle_flags | sed -e 's/ +/ /g'`
	after_flags=`echo $after_flags | sed -e 's/ +/ /g'`
	if [ $ret -ne 0 ]; then
		if [ -e "$converting_name" ]; then
			rm "$converting_name"
		fi
		command="$FFMPEG $before_flags \"$src_name\" $middle_flags \"$dst_name\" $after_flags"
		echo "==>running '$command'"
		$FFMPEG $before_flags "$src_name" $middle_flags "$dst_name" $after_flags
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
		line=`ffprobe -i "$name" 2>&1 | grep "Stream #.*Video:"`
		src_encoding_format=${line##*Video: }
		src_encoding_format=${src_encoding_format%% *}
		resolution=`echo $line | grep -P '(\d{3,})x(\d{3,})' -o`
		echo $resolution
		height=${resolution#*x}
		base_bitrate=2000
		if [ $height -ge 1080 ]; then
			base_bitrate=1200
		elif [ $height -ge 720 ]; then
			base_bitrate=800
		elif [ $height -ge 480 ]; then
			base_bitrate=500
		else
			base_bitrate=300
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
		echo "==>begin encoding: $name"
		echo "src_name=<$name>, dst_name=<$dst_name>"
		echo "src_bitrate=$src_bitrate_value, dst_bitrate=$dst_bitrate_value"

		dbr=$dst_bitrate_value$bitrate_unit
		ret=1
		try_ffmpeg $ret "$HWACCEL -i @$name@ $COMMON_FLAGS             $HWENCODE  $dbr @$converting_name@"; ret=$?
		try_ffmpeg $ret "         -i @$name@ $COMMON_FLAGS             $HWENCODE  $dbr @$converting_name@"; ret=$?
		try_ffmpeg $ret "         -i @$name@ $COMMON_FLAGS             $CPUENCODE $dbr @$converting_name@"; ret=$?
		try_ffmpeg $ret "$HWACCEL -i @$name@ $COMMON_FLAGS $AUDIO_COPY $HWENCODE  $dbr @$converting_name@"; ret=$?
		try_ffmpeg $ret "         -i @$name@ $COMMON_FLAGS $AUDIO_COPY $HWENCODE  $dbr @$converting_name@"; ret=$?
		try_ffmpeg $ret "         -i @$name@ $COMMON_FLAGS $AUDIO_COPY $CPUENCODE $dbr @$converting_name@"; ret=$?

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
	sleep 1
	total_finished=0
	total_ignored=0
	total_failed=0
	unset convertings
	convertings=()
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
			convertings[$running_count]=$converting
			((running_count++))
		fi
	done
	date_str=`date +%H:%M:%S`
	echo -e "\r$date_str: run_process: $running_count, total_files: $file_count, finished: $total_finished, failed: $total_failed ignored: $total_ignored, converting: (${convertings[@]})\c"
	#echo "$date_str: run_process: $running_count, total_files: $file_count, finished: $total_finished, failed: $total_failed ignored: $total_ignored, converting: (${convertings[@]})"
done
echo ""