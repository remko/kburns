# kburns: Generate slideshows with Ken Burns effect

Script to generate a slideshow movie with the Ken Burns effect,
using [FFmpeg](http://ffmpeg.org).

Example usage:

```ruby
$ brew install ffmpeg
$ gem install bundler
$ bundle install
$ ruby kburns.rb --size=480x300 <your property id> <my awesome video name>.mp4
```

