#!/usr/bin/env ruby

require 'fastimage'
require 'optparse'
require 'ostruct'
require 'thread/pool'

IMAGE_EXTENSIONS = ["jpg", "jpeg"]
VIDEO_EXTENSIONS = ["mp4", "mpg", "avi"]
AUDIO_EXTENSIONS = ["mp3", "ogg", "flac"]

################################################################################
# Parse options
################################################################################

$options = OpenStruct.new
$options.output_width = 1920
$options.output_height = 1080
$options.slide_duration_s = 5
$options.fade_duration_s = 1
$options.fps = 24
$options.zoom_rate = 0.1
$options.zoom_direction = "random"
$options.scale_mode = :auto
$options.codec = "libx264"
$options.verbose = false
$options.batch_size = 50
$options.reduce_slides_rounds = 1
$options.delete_temp_files = false
$options.subs_file = nil
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options] input1 [input2...] output"
  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
  opts.on("--size=[WIDTHxHEIGHT]", "Output width (default: #{$options.output_width}x#{$options.output_height})") do |s|
    size = s.downcase.split("x")
    $options.output_width = size[0].to_i
    $options.output_height = size[1].to_i
  end
  opts.on("--slide-duration=[DURATION]", Float, "Slide duration (seconds) (default: #{$options.slide_duration_s})") do |s|
    $options.slide_duration_s = s
  end
  opts.on("--fade-duration=[DURATION]", Float, "Slide duration (seconds) (default: #{$options.fade_duration_s})") do |s|
    $options.fade_duration_s = s
  end
  opts.on("--fps=[FPS]", Integer, "Output framerate (frames per second) (default: #{$options.fps})") do |n|
    $options.fps = n
  end
  opts.on("--zoom-direction=[DIRECTION]", ["random"] + ["top", "center", "bottom"].product(["left", "center", "right"], ["in", "out"]).map {|m| m.join("-")}, "Zoom direction (default: #{$options.zoom_direction})") do |t|
    $options.zoom_direction = t
  end
  opts.on("--zoom-rate=[RATE]", Float, "Zoom rate (default: #{$options.zoom_rate})") do |n|
    $options.zoom_rate = n
  end
  opts.on("--scale-mode=[SCALE_MODE]", [:pad, :pan, :crop_center], "Scale mode (pad, crop_center, pan) (default: #{$options.scale_mode})") do |n|
    $options.scale_mode = n
  end
  opts.on("--codec=[CODEC]", "Use a specific encoder") do |s|
    $options.codec = s
  end
  opts.on("--verbose", "Print information about the internal calculations") do
    $options.verbose = true
  end
  opts.on("--delete-temp-files", "Delete temporary files on exit") do
    $options.delete_temp_files = true
  end
  opts.on("--subtitles=[FILE]", "Use FILE as subtitle track") do |f|
    $options.subs_file = f
  end
end.parse!

if ARGV.length < 2
  puts "Need at least 1 input file and output file"
  exit 1
end
input_files = ARGV[0..-2]
output_file = ARGV[-1]

if $options.subs_file and !output_file.end_with?(".mkv")
  puts "Subtitles only available with MKV output"
end

################################################################################

# noinspection RubyResolve
def generate_reduced_slide(slides, prefix)
  if $options.verbose
    puts("REDUCING IMAGES SLIDES TO SINGLE VIDEO")
    puts(slides.map {|slide| slide[:file]}.join('+'))
  end

  base_offset = slides[0][:offset_s]
  file = "temp-kburns-#{prefix}-#{base_offset}.mp4"
  puts("=> #{file}") if $options.verbose
  total_duration = slides.inject(0) {|sum, slide| sum + slide[:duration_s] - $options.fade_duration_s } + $options.fade_duration_s

  # Base black image
  filter_chains = [
      "color=c=black:r=#{$options.fps}:size=#{$options.output_width}x#{$options.output_height}:d=#{total_duration}[black]"
  ]

  filter_chains += slides.each_with_index.map do |slide, i|
    filters = []

    # Fade filter
    if $options.fade_duration_s > 0
      filters << "fade=t=in:st=0:d=#{$options.fade_duration_s}:alpha=1" if i > 0
      filters << "fade=t=out:st=#{slide[:duration_s]-$options.fade_duration_s}:d=#{$options.fade_duration_s}:alpha=1" if i < slides.length - 1
    end

    # Time
    filters << "setpts=PTS-STARTPTS+#{slide[:offset_s] - base_offset}/TB"

    # All together now
    "[#{i}:v]" + filters.join(",") + "[v#{i}]"
  end

  # Overlays
  filter_chains += slides.each_index.map do |i|
    input_1 = i > 0 ? "ov#{i-1}" : "black"
    input_2 = "v#{i}"
    output = i == slides.count - 1 ? "out" : "ov#{i}"
    overlay_filter = "overlay" + (i == slides.count - 1 ? "=format=yuv420" : "")
    "[#{input_1}][#{input_2}]#{overlay_filter}[#{output}]"
  end

  cmd = [
      "ffmpeg", "-y", "-hide_banner",
      *slides.map { |slide| ["-i", "#{slide[:file]}"] }.flatten,
      "-filter_complex", filter_chains.join(";"),
      "-map", "[out]",
      "-crf", "0" ,"-preset", "ultrafast", "-tune", "stillimage",
      "-c:v", "libx264", file
  ]
  if File.exist? file
    puts("Reusing existing temp file #{file}") if $options.verbose
  else
    puts(cmd.join(' ')) if $options.verbose
    system(*cmd)
  end

  {
      video: false,
      file: file,
      duration_s: total_duration,
      offset_s: base_offset
  }
end

# reduce consecutive image videos to single, larger, videos to reduce memory consumption in last step
def reduce_slides(slides, prefix)
  reduced = []
  j = -1
  slides.each_with_index do |slide, i|
    if slide[:video]
      if j != -1
        if i - j > 1
          reduced << generate_reduced_slide(slides[j..i-1], prefix)
        else
          reduced << slides[j]
        end
      end
      reduced << slide
      j = -1
    else
      j = i if j == -1
      if j != -1 and i - j >= $options.batch_size
        reduced << generate_reduced_slide(slides[j..i], prefix)
        j = -1
      end
    end
  end
  if j != -1
    if slides.length - 1 != j
      reduced << generate_reduced_slide(slides[j..slides.length - 1], prefix)
    else
      reduced << slides[j]
    end
  end

  reduced
end

def srt_times(slide)
  offset_s = slide[:offset_s]
  srt_start = Time.at(offset_s).utc.strftime("%H:%M:%S,%3N")
  srt_end = Time.at(offset_s + slide[:duration_s]).utc.strftime("%H:%M:%S,%3N")
  "#{srt_start} --> #{srt_end}"
end

def generate_srt_file(slides)
  subtitle_index = 1
  open("temp-kburns-subs.srt", "w") do |f|
    IO.foreach($options.subs_file) do |line|
      begin
        line_parts = line.partition(' ')
        slide = slides.select {|slide| slide[:file].rpartition('/')[2].start_with?(line_parts[0])}.first
        if slide
          f.puts(subtitle_index)
          f.puts(srt_times(slide))
          f.puts(line_parts[2])
          f.puts("")
          subtitle_index += 1
        else
          puts "Ignoring subtitle line #{line}"
        end
      rescue StandardError => e
        puts "Exception generating srt, index #{subtitle_index}, line: #{line}"
        raise e
      end
    end
  end
end

################################################################################

if $options.zoom_direction == "random"
  x_directions = [:left, :right]
  y_directions = [:top, :bottom]
  z_directions = [:in, :out]
else
  x_directions = [$options.zoom_direction.split("-")[1].to_sym]
  y_directions = [$options.zoom_direction.split("-")[0].to_sym]
  z_directions = [$options.zoom_direction.split("-")[2].to_sym]
end

output_ratio = $options.output_width.to_f / $options.output_height.to_f
current_offset_s = 0

slides = []
background_tracks = []
input_files.each do |file|
  if VIDEO_EXTENSIONS.include? file.downcase.rpartition(".").last
    duration = `ffprobe -show_entries format=duration -v error -of default=noprint_wrappers=1:nokey=1 #{file}`
    this_offset_s = current_offset_s
    current_offset_s = current_offset_s + duration.to_f - $options.fade_duration_s
    slides << {
        video: true,
        file: file,
        duration_s: duration.to_f,
        offset_s: this_offset_s
    }
  elsif IMAGE_EXTENSIONS.include? file.downcase.rpartition(".").last
    size = FastImage.size(file)
    ratio = size[0].to_f / size[1].to_f
    this_offset_s = current_offset_s
    current_offset_s = current_offset_s + $options.slide_duration_s - $options.fade_duration_s
    slides << {
        video: false,
        file: file,
        width: size[0],
        height: size[1],
        duration_s: $options.slide_duration_s,
        offset_s: this_offset_s,
        direction_x: x_directions.sample,
        direction_y: y_directions.sample,
        direction_z: z_directions.sample,
        scale: if $options.scale_mode == :auto
                 (ratio - output_ratio).abs > 0.5 ? :pad : :crop_center
               else
                 $options.scale_mode
               end
    }
  elsif AUDIO_EXTENSIONS.include? file.downcase.rpartition(".").last
    background_tracks << {
        file: file
    }
  else
    raise 'Unknown file type (by extension): ' + file
  end
end

if $options.verbose
  puts("SLIDES:")
  puts(slides)
  puts("BACKGROUND TRACKS:")
  puts(background_tracks)
end

#
# Generate subtitles (srt) file from subtitles descriptor (propietary) file
#
generate_srt_file(slides) if $options.subs_file

total_duration = slides.inject(0) {|sum, slide| sum + slide[:duration_s] - $options.fade_duration_s }

if $options.verbose
  puts("TOTAL DURATION: #{total_duration} s")
  puts("GENERATE INTERMEDIATE VIDEOS FROM STILL IMAGES:")
end

# workaround a float bug in zoompan filter that causes a jitter/shake
# https://superuser.com/questions/1112617/ffmpeg-smooth-zoompan-with-no-jiggle/1112680#1112680
# https://trac.ffmpeg.org/ticket/4298
supersample_width = $options.output_width*4
supersample_height = $options.output_height*4

thread_pool = Thread.pool(5)

#
# Generate videos from still images with Ken Burns effects
#

slides.select {|slide| !slide[:video]}.each_with_index do |slide,i|
  slide_filters = []
  slide_filters << "format=pix_fmts=yuva420p"

  ratio = slide[:width].to_f / slide[:height].to_f

  # Crop to make video divisible
  slide_filters << "crop=w=2*floor(iw/2):h=2*floor(ih/2)"

  # Pad filter
  if slide[:scale] == :pad or slide[:scale] == :pan
    width, height = ratio > output_ratio ?
                        [slide[:width], (slide[:width] / output_ratio).to_i]
                        :
                        [(slide[:height] * output_ratio).to_i, slide[:height]]
    slide_filters << "pad=w=#{width}:h=#{height}:x='(ow-iw)/2':y='(oh-ih)/2'"
  end

  # Zoom/pan filter
  z_step = $options.zoom_rate.to_f / ($options.fps * $options.slide_duration_s)
  z_rate = $options.zoom_rate.to_f
  z_initial = 1
  if slide[:scale] == :pan
    z_initial = ratio / output_ratio
    z_step = z_step * ratio / output_ratio
    z_rate = z_rate * ratio / output_ratio
    if ratio > output_ratio
      if (slide[:direction_x] == :left && slide[:direction_z] != :out) || (slide[:direction_x] == :right && slide[:direction_z] == :out)
        x = "(1-on/(#{$options.fps}*#{$options.slide_duration_s}))*(iw-iw/zoom)"
      elsif (slide[:direction_x] == :right && slide[:direction_z] != :out) || (slide[:direction_x] == :left && slide[:direction_z] == :out)
        x = "(on/(#{$options.fps}*#{$options.slide_duration_s}))*(iw-iw/zoom)"
      else
        x = "(iw-ow)/2"
      end
      y_offset = "(ih-iw/#{ratio})/2"
      y = case slide[:direction_y]
          when :top
            y_offset
          when :center
            "#{y_offset}+iw/#{ratio}/2-iw/#{output_ratio}/zoom/2"
          when :bottom
            "#{y_offset}+iw/#{ratio}-iw/#{output_ratio}/zoom"
          end
    else
      z_initial = output_ratio / ratio
      z_step = z_step * output_ratio / ratio
      z_rate = z_rate * output_ratio / ratio
      x_offset = "(iw-#{ratio}*ih)/2"
      x = case slide[:direction_x]
          when :left
            x_offset
          when :center
            "#{x_offset}+ih*#{ratio}/2-ih*#{output_ratio}/zoom/2"
          when :right
            "#{x_offset}+ih*#{ratio}-ih*#{output_ratio}/zoom"
          end
      if (slide[:direction_y] == :top && slide[:direction_z] != :out) || (slide[:direction_y] == :bottom && slide[:direction_z] == :out)
        y = "(1-on/(#{$options.fps}*#{$options.slide_duration_s}))*(ih-ih/zoom)"
      elsif (slide[:direction_y] == :bottom && slide[:direction_z] != :out) || (slide[:direction_y] == :top && slide[:direction_z] == :out)
        y = "(on/(#{$options.fps}*#{$options.slide_duration_s}))*(ih-ih/zoom)"
      else
        y = "(ih-oh)/2"
      end
    end
  else
    x = case slide[:direction_x]
        when :left
          "0"
        when :center
          "iw/2-(iw/zoom/2)"
        when :right
          "iw-iw/zoom"
        end
    y = case slide[:direction_y]
        when :top
          "0"
        when :center
          "ih/2-(ih/zoom/2)"
        when :bottom
          "ih-ih/zoom"
        end
  end
  z = case slide[:direction_z]
      when :in
        "if(eq(on,1),#{z_initial},zoom+#{z_step})"
      when :out
        "if(eq(on,1),#{z_initial + z_rate},zoom-#{z_step})"
      end
  width, height = case slide[:scale]
                  when :crop_center
                    if output_ratio > ratio
                      [$options.output_width, ($options.output_width / ratio).to_i]
                    else
                      [($options.output_height * ratio).to_i, $options.output_height]
                    end
                  when :pan, :pad
                    [$options.output_width, $options.output_height]
                  end

  slide_filters << "scale=#{supersample_width}x#{supersample_height},zoompan=z='#{z}':x='#{x}':y='#{y}':fps=#{$options.fps}:d=#{$options.fps}*#{$options.slide_duration_s}:s=#{width}x#{height}"

  # Crop filter
  if slide[:scale] == :crop_center
    crop_x = "(iw-ow)/2"
    crop_y = "(ih-oh)/2"
    slide_filters << "crop=w=#{$options.output_width}:h=#{$options.output_height}:x='#{crop_x}':y='#{crop_y}'"
  end

  # Generate image video with Ken Burns effect
  slide[:tempvideo] = "temp-kburns-#{i}.mp4"
  cmd = [
      "ffmpeg", "-y", "-hide_banner", "-v", "quiet",
      "-i", slide[:file],
      "-filter_complex", slide_filters.join(','),
      "-crf", "0" ,"-preset", "ultrafast", "-tune", "stillimage",
      "-c:v", "libx264", slide[:tempvideo]
  ]

  if File.exists? slide[:tempvideo]
    puts("Reusing existing temp file #{slide[:tempvideo]}") if $options.verbose
  else
    puts("#{slide[:file]} => #{slide[:tempvideo]} : " + cmd.join(' ')) if $options.verbose
    thread_pool.process { system(*cmd) }
  end
  slide[:file] = slide[:tempvideo]
end

# wait for threads
if $options.verbose
  puts("WAITING FOR #{thread_pool.backlog} THREADS")
end
thread_pool.shutdown

#
# reduce consecutive image videos to single, larger, videos
#

$options.reduce_slides_rounds.times do |i|
  slides = reduce_slides(slides, "reduce#{i+1 > 1 ? i+1 : ''}")
end

if $options.verbose
  puts("REDUCED SLIDES:")
  puts(slides)
end

#
# Generate final video (without any audio)
#

# Base black image
filter_chains = [
  "color=c=black:r=#{$options.fps}:size=#{$options.output_width}x#{$options.output_height}:d=#{total_duration}[black]"
]

# Slide filterchains
filter_chains += slides.each_with_index.map do |slide, i|
  filters = []

  if slide[:video]
    filters << "scale=w=#{$options.output_width}:h=-1"
  end

  # Fade filter
  if $options.fade_duration_s > 0
    filters << "fade=t=in:st=0:d=#{$options.fade_duration_s}:alpha=#{i == 0 ? 0 : 1}"
    filters << "fade=t=out:st=#{slide[:duration_s]-$options.fade_duration_s}:d=#{$options.fade_duration_s}:alpha=#{i == slides.count - 1 ? 0 : 1}"
  end

  # Time
  filters << "setpts=PTS-STARTPTS+#{slide[:offset_s]}/TB"

  # All together now
  "[#{i}:v]" + filters.join(",") + "[v#{i}]"
end

# Overlays
filter_chains += slides.each_index.map do |i|
  input_1 = i > 0 ? "ov#{i-1}" : "black"
  input_2 = "v#{i}"
  output = i == slides.count - 1 ? "out" : "ov#{i}"
  overlay_filter = "overlay" + (i == slides.count - 1 ? "=format=yuv420" : "")
  "[#{input_1}][#{input_2}]#{overlay_filter}[#{output}]"
end

if $options.verbose
  puts("FINAL VIDEO, CHAINS:")
  puts(filter_chains)
end

# Run ffmpeg
final_video_file = "temp-kburns-video.mp4"
cmd = [
    "ffmpeg", "-hide_banner", "-y",
    *slides.map { |slide| ["-i", "#{slide[:file]}"] }.flatten,
    "-filter_complex_script", "temp-kburns-video-script.txt",
    "-t", (total_duration+$options.fade_duration_s).to_s,
    "-map", "[out]",
    "-preset", "ultrafast", "-tune", "stillimage",
    "-c:v", $options.codec, final_video_file
]

if $options.verbose
  puts "FFMPEG COMMAND LINE"
  puts cmd.join(" ")
end

File.write('temp-kburns-video-script.txt', filter_chains.join(";\n"))
if File.exist? final_video_file
  puts("Reusing existing final video file: #{final_video_file}")
else
  system(*cmd)
end

#
# Generate complete audio track, with audio from video slides and background music on image slides
#
video_slides = slides.select {|slide| slide[:video]}
filter_chains = []

# audio from video slides
audio_tracks = []
video_slides.each_with_index do |slide,i|
  if slide[:video]
    filters = []

    # Fade filter
    if $options.fade_duration_s > 0
      filters << "afade=t=in:st=0:d=#{$options.fade_duration_s}"
      filters << "afade=t=out:st=#{slide[:duration_s]-$options.fade_duration_s}:d=#{$options.fade_duration_s}"
    end

    filters << "adelay=#{(slide[:offset_s] * 1000).to_i}|#{(slide[:offset_s] * 1000).to_i}"
    filter_chains << "[#{i}:a]" + filters.join(",") + "[a#{i}]"
    audio_tracks << "[a#{i}]"
  end
end

music_input_offset = video_slides.length

# background audio
filter_chains << background_tracks.each_index.map {|i| "[#{i + music_input_offset}:a]"}.join("") +
    "concat=n=#{background_tracks.length}:v=0:a=1[background_audio]"

# background audio fades (one per "section" of images)
background_sections = []
section_start = slides[0][:video] ? nil : 0
slides.each do |slide|
  if slide[:video]
    unless section_start.nil?
      background_sections << { st: section_start, end: slide[:offset_s] }
      section_start = nil
    end
  else
    if section_start.nil?
      section_start = slide[:offset_s]
    end
  end
end
unless section_start.nil?
  background_sections << { st: section_start, end: total_duration }
end

if $options.verbose
  puts("BACKGROUND AUDIO SECTIONS:")
  puts(background_sections)
end

# split the background track into the necessary copies for the fades
filter_chains << "[background_audio]asplit=#{background_sections.size}" + background_sections.each_index.map {|i| "[b#{i}]"}.join('')

filter_chains << background_sections.each_with_index.map do |section, i|
  audio_tracks << "[b#{i}f]"
  "[b#{i}]afade=t=in:st=#{section[:st]}:d=#{$options.fade_duration_s},afade=t=out:st=#{section[:end]}:d=#{$options.fade_duration_s}[b#{i}f]"
end

# audio mix
filter_chains << audio_tracks.join('') + "amix=inputs=" + audio_tracks.length.to_s + "[aout]"

if $options.verbose
  puts("FINAL AUDIO, CHAINS:")
  puts(filter_chains)
end

# Run ffmpeg
final_audio_file = "temp-kburns-audio.m4a"
cmd = [
    "ffmpeg", "-hide_banner", "-y",
    *video_slides.map { |slide| ["-i", "#{slide[:file]}"] }.flatten,
    *background_tracks.map { |trk| ["-i", "#{trk[:file]}"] }.flatten,
    "-filter_complex_script", "temp-kburns-audio-script.txt",
    "-t", (total_duration+$options.fade_duration_s).to_s,
    "-map", "[aout]",
    "-c:a", "aac", "-b:a", "160k", final_audio_file
]

if $options.verbose
  puts "FFMPEG COMMAND LINE"
  puts cmd.join(" ")
end

File.write('temp-kburns-audio-script.txt', filter_chains.join(";\n"))
if File.exist? final_audio_file
  puts("Reusing existing final video file: #{final_audio_file}")
else
  system(*cmd)
end

#
# Final mux
#

cmd = [
    "ffmpeg", "-hide_banner", "-y",
    "-i", final_video_file,
    "-i", final_audio_file,
    *$options.subs_file ? ["-i", "temp-kburns-subs.srt"] : [],
    "-c", "copy", "-disposition:s:0", "default", output_file
]

if $options.verbose
  puts cmd.join(" ")
end
system(*cmd)

Dir.glob('temp-kburns*').each {|file| File.delete(file)} if $options.delete_temp_files
