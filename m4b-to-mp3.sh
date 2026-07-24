#!/bin/bash
#
# Dependencies:
#   ffmpeg id3v2 jq
#
# Copyright 2026 Joshua White
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.

usage="$(basename "$0") [-h] input_file(s) -- script to split an M4B audiobook by chapters and convert to MP3

where:
    -h  show this help text
    -b  target MP3 bitrate in kbps (default 192)
    -c  write files as [CHAPTER NUM] [CHAPTER TITLE] rather than [CHAPTER NUM] [BOOK TITLE], [CHAPTER TITLE]
    -v  enabled verbose (debugging) output
    
Files are output to the source directory. The script does not overwrite existing files."


# GLOBALS

VERBOSE=false
FULL_TITLE=true
BITRATE=192



# FUNCTIONS

function validate_audio() {
    # Use ffprobe to check the file format
    # Keep as separate function to allow easy changes to this test in future if required (e.g. adding different formats)
    ftype=`ffprobe -v quiet -show_entries format=format_name -of default=noprint_wrappers=1:nokey=1 -i "$1"`
    if $VERBOSE; then echo "Detected file format = $ftype"; fi
    
    # Check if matching file type
    if [[ "$ftype" =~ "m4a" ]]
    then return 0 # "True" case / format matches
    else return 1 # "False" case / format does not match
    fi
}

function extract_chapters() {
    audiobook=$1
       
    # Extract path to audiobook
    target_dir=`dirname "$audiobook"`

    # Use ffprobe to read the metadata and audiobook chapters and output it as JSON
    metajson=`ffprobe -of json -show_entries format_tags -i "$audiobook" -loglevel error -print_format json -show_chapters`
       
    # TODO: Extract rest of metadata to add to individual MP3s
    echo $metajson | jq .format.tags
    booktitle=`echo $metajson | jq -r .format.tags.title`
    
    # Count chapters
    cnum=`echo $metajson | jq '.chapters | length'`
    digits=$((${#cnum}+1))
    if $VERBOSE; then echo "$cnum chapter(s) detected"; fi
    
    # Iterate through the chapters
    echo $metajson | jq -c .chapters[] | while read chapter; do

       # Build the chapter name string as [CHAPTER NUM] [CHAPTER TITLE] -- e.g. "01 Hello, World"
       chapter_name=`echo $chapter | jq --argjson digits "$digits" -r 'include "jq_filters"; (.id | tonumber | .+1 | pad_left($digits)) + " " + .tags.title'`

       # Radio plays and audio dramas (typically broken into multiple parts with the chapter title as Part #N)
       # Create the name as [CHAPTER NUM] [BOOK TITLE], [CHAPTER TITLE] -- eg. "01 The Sirens of Time, Part 1"
       if $FULL_TITLE && [[ "$chapter_name" =~ "Part" ]]
       then track_name=`echo $chapter | jq --argjson digits "$digits" --arg booktitle "$booktitle" -r 'include "jq_filters"; (.id | tonumber | .+1 | pad_left($digits)) + " " + $booktitle + ", " + .tags.title'`
       else track_name=$chapter_name
       fi

       if $VERBOSE; then echo "Creating $target_dir/$track_name.mp3 ..."; fi
       
       # Build ffmpeg command
       chapter_split=`echo $chapter | jq -r '"-ss " + .start_time + " -to " + .end_time'`

       # This must be piped to dev/null or ffmpeg messes with the JSON in the loop
       </dev/null ffmpeg -n -loglevel error -i "$audiobook" $chapter_split -codec:a libmp3lame -ab ${BITRATE}k "$target_dir/$track_name.mp3"
    done
}



# CLI

while getopts ':hb:cv' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    b) BITRATE=$OPTARG
       ;;
    c) FULL_TITLE=false
       ;;
    v) VERBOSE=true
       ;;
   \?) printf "illegal option: -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit 1
       ;;
  esac
done

shift $((OPTIND - 1))

# Error handling (check input)
if [ $# -eq 0 ]; then
    echo "Error: No input files specified" >&2
    usage
fi


# MAIN

if $VERBOSE; then echo "MP3 encoding bitrate set to ${BITRATE}kbps"; fi

# Iterate through all files provided
for file in "$@"; do
    if [ ! -f "$file" ]; then
        echo "Warning: '$file' not found, skipping" >&2
        continue
    fi
    
    if $VERBOSE; then echo "Processing $file"; fi

    # Probe the file and confirm correct file type
    if validate_audio "$file"
    then
       # Probe file and extract metadata and chapters
       extract_chapters "$file"
    else
       echo "$file does not appear to be an M4A audio format"
       continue
    fi
done

