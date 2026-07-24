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
    -g  set a custom genre (default is to use the M4B genre field)
    -c  write files as [CHAPTER NUM] [CHAPTER TITLE] rather than [CHAPTER NUM] [BOOK TITLE], [CHAPTER TITLE]
    -d  create a subdirectory for the MP3 files based on the album field (based on use of -t option)
    -s  swap album artist and artist fields
    -t  set the MP3 album to the M4B fields [SHOW TITLE] [EPISODE]: [TITLE] instead of [ALBUM]
    -o  overwrite existing file
    -v  enabled verbose (debugging) output
    
Files are output to the source audiobook directory."


# GLOBALS

EXIT_CODE=0
VERBOSE=false
FULL_TITLE=true
SUBDIR=false
BITRATE=192
GENRE=""
SWAP_ARTISTS=false
SHOW_TITLE=false
OVERWRITE=false


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
    local_exit_code=0
       
    # Extract path to audiobook
    target_dir=`dirname "$audiobook"`
    
    # Use ffprobe to read the metadata and audiobook chapters and output it as JSON
    metajson=`ffprobe -of json -show_entries format_tags -i "$audiobook" -loglevel error -print_format json -show_chapters`
       
    # Uncomment this line for debugging audiobook metadata
    #echo $metajson | jq .format.tags

    # Extract audiobook metadata to add to individual MP3s
    # Use of select stops string "null" ending up in ID3v2 tags if a field isn't present
    bookjson=`echo $metajson | jq .format.tags`
    booktitle=`echo $bookjson | jq -r 'select(.title != null) | .title'`
    artist=`echo $bookjson | jq -r 'select(.artist != null) | .artist'`
    albumartist=`echo $bookjson | jq -r 'select(.album_artist != null) | .album_artist'`
    albumdate=`echo $bookjson | jq -r 'select(.date != null) | .date'`
    composer=`echo $bookjson | jq -r 'select(.composer != null) | .composer'`

    if $SHOW_TITLE
    then
        # Use the show title, episode number and episode title for the album
        album=`echo $bookjson | jq -r '(select(.show != null) | .show) + " " + (select(.episode_sort != null) | .episode_sort) + ": " + (select(.title != null) | .title)'`
    else
        # Use the album field provided by the audiobook (default)
        album=`echo $bookjson | jq -r 'select(.album != null) | .album'`
    fi
    
    if $SUBDIR
    then
        # Remove the colon added if using the show title and episode number
        full_path="$target_dir/${album//:/}"
        
        # Create subdirectory for MP3 files
        mkdir -p "$full_path"
        target_dir="$full_path"
    fi
    if $VERBOSE; then echo "Output path set to $target_dir"; fi

    if [ -z "$GENRE" ]
    then
        # If no user-specified genre available, fallback to the provided genre field
        GENRE=`echo $bookjson | jq -r 'select(.genre != null) | .genre'`
    fi
    
    # Count chapters
    cnum=`echo $metajson | jq '.chapters | length'`
    digits=$((${#cnum}+1))
    if $VERBOSE; then echo "$cnum chapter(s) detected"; fi
    
    # Iterate through the chapters
    while read chapter; do
        track_num=`echo $chapter | jq -r '.id | tonumber | .+1'`

        # Build the chapter name string as [CHAPTER NUM] [CHAPTER TITLE] -- e.g. "01 Hello, World"
        chapter_name=`echo $chapter | jq --argjson digits "$digits" -r 'include "jq_filters"; (.id | tonumber | .+1 | pad_left($digits)) + " " + .tags.title'`

        # Radio plays and audio dramas (typically broken into multiple parts with the chapter title as Part #N)
        # Create the name as [CHAPTER NUM] [BOOK TITLE], [CHAPTER TITLE] -- eg. "01 The Sirens of Time, Part 1"
        if $FULL_TITLE && [[ "$chapter_name" =~ "Part" ]]
        then
            track_name=`echo $chapter | jq --argjson digits "$digits" --arg booktitle "$booktitle" -r 'include "jq_filters"; (.id | tonumber | .+1 | pad_left($digits)) + " " + $booktitle + ", " + .tags.title'`
            track_title=`echo $chapter | jq --arg booktitle "$booktitle" -r '$booktitle + ", " + .tags.title'`
        else
            track_name=$chapter_name
            track_title=`echo $chapter | jq -r .tags.title`
        fi
        
        if [ -f "${target_dir}/${track_name}.mp3" ] && [ $OVERWRITE == "false" ]
        then
            echo "$target_dir/$track_name.mp3 already exists"
            local_exit_code=73
        else
            echo "Creating $target_dir/$track_name.mp3 ..."

            # Build ffmpeg command
            chapter_split=`echo $chapter | jq -r '"-ss " + .start_time + " -to " + .end_time'`

            # This must be piped to dev/null or ffmpeg messes with the JSON in the loop
            </dev/null ffmpeg -y -loglevel error -i "$audiobook" $chapter_split -codec:a libmp3lame -ab ${BITRATE}k "$target_dir/$track_name.mp3"
            
            # Set ID3v2 tags
            id3v2 --song "$track_title" --album "$album" --track $track_num -g "$GENRE" -y "$albumdate" --TCOM "$composer" "$target_dir/$track_name.mp3"
            
            if $SWAP_ARTISTS
            then
                id3v2 --TPE1 "$albumartist" --TPE2 "$artist" "$target_dir/$track_name.mp3"
            else
                id3v2 --TPE1 "$artist" --TPE2 "$albumartist" "$target_dir/$track_name.mp3"
            fi
        fi
    done <<< $(echo $metajson | jq -c .chapters[])
    
    return $local_exit_code
}



# CLI

while getopts ':hb:g:cdstov' option; do
  case "$option" in
    h) echo "$usage"
       exit
       ;;
    b) BITRATE=$OPTARG
       ;;
    g) GENRE=$OPTARG
       ;;
    c) FULL_TITLE=false
       ;;
    d) SUBDIR=true
       ;;
    s) SWAP_ARTISTS=true
       ;;
    t) SHOW_TITLE=true
       ;;
    o) OVERWRITE=true
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
        if [ $EXIT_CODE -eq 0 ]; then EXIT_CODE=66; fi
        continue
    fi
    
    if $VERBOSE; then echo "Processing $file"; fi

    # Probe the file and confirm correct file type
    if validate_audio "$file"
    then
       # Probe file and extract metadata and chapters
       extract_chapters "$file"
       ec=$?
       if [ $EXIT_CODE -eq 0 ]; then EXIT_CODE=$ec; fi
    else
       echo "$file does not appear to be an M4A audio format"
       if [ $EXIT_CODE -eq 0 ]; then EXIT_CODE=65; fi
       continue
    fi
done

exit $EXIT_CODE
