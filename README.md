# ffmpeg encode
## 1. description
This scripts can encode video in HEVC(H265) format to reduce size. All encoded video files will be stored in 'converted' directory and the corresponding source video files will be stored in 'finished' directory

You must have ffmpeg.exe installed and add the directory into PATH env

## 2. using
In windows, using git bash, and set encode.sh directory in PATH env

```bash
#encode all the video files in current directory
encode.sh

#encode all the mp4 files in current directory, and set overall bitrate 1200kb/s
encode.sh *.mp4 1200

#encode all the video files in 'video_dir' directory, bitrate=1200kb/s
encode.sh video_dir 1200

#encode all the subdir videos
for subdir in video_dir/*; do encode.sh "$subdir"; done

#only save video and audio stream
export EXTERNAL_MAP_FLAGS="-map 0:v -map:a"
encode.sh
```

