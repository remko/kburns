#!/usr/bin/env ruby

require 'fastimage'
require 'optparse'
require 'ostruct'
require 'open3'
require 'tempfile'

################################################################################
# Parse options
################################################################################

options = OpenStruct.new
options.output_width = 1280
options.output_height = 800
options.slide_duration_s = 4
options.fade_duration_s = 1
options.fps = 60
options.zoom_rate = 0.1
options.zoom_direction = "random"
options.scale_mode = :auto
options.dump_filter_graph = false
options.loopable = false
options.audio = nil
OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} [options] input1 [input2...] output"
  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
  opts.on("--size=[WIDTHxHEIGHT]", "Output width (default: #{options.output_width}x#{options.output_height})") do |s|
    size = s.downcase.split("x")
    options.output_width = size[0].to_i
    options.output_height = size[1].to_i
  end
  opts.on("--slide-duration=[DURATION]", Float, "Slide duration (seconds) (default: #{options.slide_duration_s})") do |s|
    options.slide_duration_s = s
  end
  opts.on("--fade-duration=[DURATION]", Float, "Slide duration (seconds) (default: #{options.fade_duration_s})") do |s|
    options.fade_duration_s = s
  end
  opts.on("--fps=[FPS]", Integer, "Output framerate (frames per second) (default: #{options.fps})") do |n|
    options.fps = n
  end
  opts.on("--zoom-direction=[DIRECTION]", ["random"] + ["top", "center", "bottom"].product(["left", "center", "right"], ["in", "out"]).map {|m| m.join("-")}, "Zoom direction (default: #{options.zoom_direction})") do |t|
    options.zoom_direction = t
  end
  opts.on("--zoom-rate=[RATE]", Float, "Zoom rate (default: #{options.zoom_rate})") do |n|
    options.zoom_rate = n
  end
  opts.on("--scale-mode=[SCALE_MODE]", [:pad, :pan, :crop_center], "Scale mode (pad, crop_center, pan) (default: #{options.scale_mode})") do |n|
    options.scale_mode = n
  end
  opts.on("--dump-filter-graph", "Dump filter graph to '<OUTPUT>.filtergraph.png' for debugging") do |b|
    options.dump_filter_graph = true
  end
  opts.on("--loopable", "Create loopable video") do |b|
    options.loopable = true
  end
  opts.on("--audio=[FILE]", "Use FILE as audio track") do |f|
    options.audio = f
  end
  opts.on("-y", "Overwrite output file without asking") do
    options.y = true
  end
end.parse!

if ARGV.length < 2
  puts "Need at least 1 input file and output file"
  exit 1
end
input_files = ARGV[0..-2]
output_file = ARGV[-1]


################################################################################

if options.zoom_direction == "random"
  x_directions = [:left, :right]
  y_directions = [:top, :bottom]
  z_directions = [:in, :out]
else
  x_directions = [options.zoom_direction.split("-")[1].to_sym]
  y_directions = [options.zoom_direction.split("-")[0].to_sym]
  z_directions = [options.zoom_direction.split("-")[2].to_sym]
end

output_ratio = options.output_width.to_f / options.output_height.to_f

slides = input_files.map do |file|
  size = FastImage.size(file)
  ratio = size[0].to_f / size[1].to_f
  {
    file: file,
    width: size[0],
    height: size[1],
    direction_x: x_directions.sample,
    direction_y: y_directions.sample,
    direction_z: z_directions.sample,
    scale: options.scale_mode == :auto ? 
      ((ratio - output_ratio).abs > 0.5 ? :pad : :crop_center)
    :
      options.scale_mode
  }
end
if options.loopable
  slides << slides[0]
end

# Base black image
filter_chains = [
  "color=c=black:r=#{options.fps}:size=#{options.output_width}x#{options.output_height}:d=#{(options.slide_duration_s-options.fade_duration_s)*slides.count+options.fade_duration_s}[black]"
]

# Slide filterchains
filter_chains += slides.each_with_index.map do |slide, i|
  filters = ["format=pix_fmts=yuva420p"]

  ratio = slide[:width].to_f/slide[:height].to_f

  # Crop to make video divisible
  filters << "crop=w=2*floor(iw/2):h=2*floor(ih/2)"

  # Pad filter
  if slide[:scale] == :pad or slide[:scale] == :pan
    width, height = ratio > output_ratio ?
      [slide[:width], (slide[:width]/output_ratio).to_i]
    :
      [(slide[:height]*output_ratio).to_i, slide[:height]]
    filters << "pad=w=#{width}:h=#{height}:x='(ow-iw)/2':y='(oh-ih)/2'"
  end

  # Zoom/pan filter
  z_step = options.zoom_rate.to_f/(options.fps*options.slide_duration_s)
  z_rate = options.zoom_rate.to_f
  z_initial = 1
  if slide[:scale] == :pan
    z_initial = ratio/output_ratio
    z_step = z_step*ratio/output_ratio
    z_rate = z_rate*ratio/output_ratio
    if ratio > output_ratio
      if (slide[:direction_x] == :left && slide[:direction_z] != :out) || (slide[:direction_x] == :right && slide[:direction_z] == :out)
        x = "(1-on/(#{options.fps}*#{options.slide_duration_s}))*(iw-iw/zoom)"
      elsif (slide[:direction_x] == :right && slide[:direction_z] != :out) || (slide[:direction_x] == :left && slide[:direction_z] == :out)
        x = "(on/(#{options.fps}*#{options.slide_duration_s}))*(iw-iw/zoom)"
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
      z_initial = output_ratio/ratio
      z_step = z_step*output_ratio/ratio
      z_rate = z_rate*output_ratio/ratio
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
        y = "(1-on/(#{options.fps}*#{options.slide_duration_s}))*(ih-ih/zoom)"
      elsif (slide[:direction_y] == :bottom && slide[:direction_z] != :out) || (slide[:direction_y] == :top && slide[:direction_z] == :out)
        y = "(on/(#{options.fps}*#{options.slide_duration_s}))*(ih-ih/zoom)"
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
      "if(eq(on,1),#{z_initial+z_rate},zoom-#{z_step})"
  end
  width, height = case slide[:scale]
    when :crop_center
      if output_ratio > ratio
        [options.output_width, (options.output_width/ratio).to_i]
      else
        [(options.output_height*ratio).to_i, options.output_height]
      end
    when :pan, :pad
      [options.output_width, options.output_height]
    end

  filters << "zoompan=z='#{z}':x='#{x}':y='#{y}':fps=#{options.fps}:d=#{options.fps}*#{options.slide_duration_s}:s=#{width}x#{height}"

  # Crop filter
  if slide[:scale] == :crop_center
    crop_x = "(iw-ow)/2"
    crop_y = "(ih-oh)/2"
    filters << "crop=w=#{options.output_width}:h=#{options.output_height}:x='#{crop_x}':y='#{crop_y}'"
  end

  # Fade filter
  if options.fade_duration_s > 0
    filters << "fade=t=in:st=0:d=#{options.fade_duration_s}:alpha=#{i == 0 ? 0 : 1}"
    filters << "fade=t=out:st=#{options.slide_duration_s-options.fade_duration_s}:d=#{options.fade_duration_s}:alpha=#{i == slides.count - 1 ? 0 : 1}"
  end

  # Time
  filters << "setpts=PTS-STARTPTS+#{i}*#{options.slide_duration_s-options.fade_duration_s}/TB"

  # All together now
  "[#{i}:v]" + filters.join(",") + "[v#{i}]"
end

# Overlays
filter_chains += slides.each_with_index.map do |slide, i|
  input_1 = i > 0 ? "ov#{i-1}" : "black"
  input_2 = "v#{i}"
  output = i == slides.count - 1 ? "out" : "ov#{i}"
  overlay_filter = "overlay" + (i == slides.count - 1 ? "=format=yuv420" : "")
  "[#{input_1}][#{input_2}]#{overlay_filter}[#{output}]"
end

# Dump filterchain for debugging
if options.dump_filter_graph
  filters = filter_chains.map do |f| 
    f.gsub(/^\[(\d+):v\]/) do |m| 
      slide = slides[$1.to_i]
      "nullsrc=s=#{slide[:width]}x#{slide[:height]}:r=25:sar=300/300:d=0.04,format=yuvj422p,"
    end.gsub(/\[out\]$/, ",nullsink") 
  end.join(";")
  tmp = Tempfile.new('filtergraph.dot')
  tmp.close
  # puts filters
  Open3.popen3("graph2dot", "-o", tmp.path) do |i, o, e, t|
    i.write(filters)
    i.close()
    puts(e.read)
  end
  system("dot -Tpng #{tmp.path} -o #{output_file}.filtergraph.png")
end

# Run ffmpeg
cmd = [
  "ffmpeg", "-hide_banner", *options.y ? ["-y"] : [], 
  *slides.map { |s| ["-i", s[:file]] }.flatten,
  *options.audio ? ["-i", options.audio] : [],
  "-filter_complex", filter_chains.join(";"),
  *(options.loopable ? [
    "-ss", options.fade_duration_s.to_s,
    "-t", ((options.slide_duration_s-options.fade_duration_s)*(slides.count-1)).to_s
  ] : [
    "-t", ((options.slide_duration_s-options.fade_duration_s)*slides.count+options.fade_duration_s).to_s
  ]),
  "-map", "[out]", 
  *(options.audio ? ["-map", "#{slides.count}:a"] : []),
  "-c:v", "libx264", output_file
]
puts cmd.join(" ")
system(*cmd)
