# m4b-to-mp3
Split an M4B audiobook by chapters and convert to MP3

## Background

This script was written to solve a particular problem: extracting 
the individual chapters/episodes from audio dramas and radio plays 
formatted as a single M4B audiobook file and converting them to MP3
for use with an MP3 player.

It was inspired by these scripts and discussions:

- https://github.com/AmbujSE/audiobookconverter
- https://gist.github.com/nitrag/a188b8969a539ce0f7a64deb56c00277
- https://gist.github.com/aularon/c48173f8246fa57e9c1ef7ff694ab06f
- https://unix.stackexchange.com/questions/499179/using-ffmpeg-to-split-an-audible-audio-book-into-chapters

No LLMs were used in the creation of this script.


## Dependencies

- ffmpeg
- id3v2
- jq


## Usage

The script takes a single M4B as its input argument with several 
optional parameters:

| parameter | example | description |
| --- | --- | --- |
| -b | 128 | target MP3 bitrate in kbps (default 192) |
| -c | | Boolean flag to set the template for the output filename to [CHAPTER NUM] [CHAPTER TITLE] rather than [CHAPTER NUM] [BOOK TITLE], [CHAPTER TITLE] |
| -v | | Boolean flag to enable verbose output |

The script will output the MP3 files to the source directory containing
the input M4B. It does **not** overwrite existing files.

It relies on the metadata stored in the M4B for the book and chapter titles.


# Copyright and Licence

Unless otherwise stated, these scripts are Copyright © Joshua White and 
licensed under the GNU GPL v3.0.


