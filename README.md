# kburns: Generate slideshows with Ken Burns effect

Script to generate a slideshow movie with the Ken Burns effect,
using [FFmpeg](http://ffmpeg.org).

Forked from [this project](https://github.com/remko/kburns) based on
ideas explained on [this blog post](https://el-tramo.be/blog/ken-burns-ffmpeg/)
from the same author.

The original project did ok using some pictures and a background
music track. I had some more requirements.

* Slides from both still images and video clips
* Preserve audio from the video clips
* Music background on still images slides
* Simple subtitle generator

So after a lot of iterations I got it working expanding on the ideas
of the original project. Tried with a real example folder with 700
still images, 7 short mp4 video clips and about 12 background music
tracks.

My first attempt crashed my computer when the `ffmpeg` started eating
RAM and my OS reported 57 GB of memory used (between physical and swap).

So back to the editor I had to break down the process into multiple
`ffmpeg` executions and intermediate files before muxing it all back
together.

The `kburns2.rb` is the result of this work. Still unstable, not
documented, not tested, etc. I even don't know Ruby, first time using
it.

## How to use

The simple way: just run the script with all input parameters and
the output file as the final parameter. You can mix still images,
video clips and audio tracks. The two first kinds of inputs would
become slides in the defined order. The audio files would become
the background track, also in the defined order.

```
kburns3.rb 001.JPG please.mp4 002.JPG 002b.mp4 004.JPG 005.JPG asfalto.mp3 "09 My way.mp3" out.mkv
```

You can also get some verbose information about the process with
`--verbose`.

Subtitles can be specified with a simple file where each line is
a subtitle associated with a slide.

Like this:

```
001 Day 1
002 Partying with friends
004 Wait for it!
```

This will look for a slide which filename starts with `001` and show
the text *Day 1* during that slide. It will be converted to a `srt`
file embedded in the resulting `mkv` file.

Example:

```
kburns3.rb --verbose --subtitles=subs.txt 001.JPG please.mp4 002.JPG 002b.mp4 004.JPG asfalto.mp3 out.mkv
```
