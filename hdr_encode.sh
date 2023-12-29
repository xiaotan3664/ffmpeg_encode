convert_prefix="==converting=="
converted_dir=converted
finished_dir=finished
encode_proc=${ENCODE_PROC:-1}
format=mkv

function hdr_convert() {
  local bitrate=${1:-4000}
  shift
  local files=${1:-"*"}
  shift
  local other_flags=$*
  echo $other_flags

  for filename in $files; do
    local cur_dir=`dirname $filename`
    local pure_name=`basename $filename`
    local converted_name="${cur_dir}/==converting==$pure_name"
    converted_name="${converted_name%.*}.$format"
    rm -f "$converted_name"
    nvencc --avhw -i "${filename}" \
      --video-metadata copy  \
      --metadata copy \
      --chapter-copy -c hevc \
      --vbr "$bitrate" \
      --bref-mode disabled \
      --preset quality \
      --tier high \
      --no-aq \
      --level auto \
      --chromaloc auto \
      --colorrange auto \
      --colormatrix auto \
      --transfer auto \
      --colorprim auto \
      --dhdr10-info copy \
      --output-depth 10 \
      --multipass 2pass-full \
      --mv-precision auto \
      --avsync cfr \
      --audio-copy \
      --data-copy \
      --sub-copy \
      $other_flags \
      -o "${converted_name}"

    ret=$?
    if [ $ret -eq 0 ]; then
      mkdir -p "$cur_dir/$converted_dir" "$cur_dir/$finished_dir"
      mv "$filename" "$cur_dir/$finished_dir"
      mv "$converted_name" "$cur_dir/$converted_dir/${pure_name%.*}.$format"
      echo "'$filename' converted success!"
    else
      echo "'$filename' converted failed!"
    fi
  done
}

bitrate=${1:-4000}
shift
files=${1:-"*"}
shift

#rm -f "`dirname "$files"`/${convert_prefix}"*
ls $files
hdr_convert "$bitrate" "$files" $*
