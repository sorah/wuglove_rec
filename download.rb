require 'nokogiri'
require 'fileutils'
require 'json'
require 'uri'
require 'open-uri'

class WugloveMovieDownload
  def initialize(pages_dir, output_dir)
    @pages_dir = pages_dir
    @output_dir = output_dir
  end

  def run
    page_paths.each_with_index do |page_path, idx|
      puts "    #{idx+1}/#{page_paths.size}"
      download page_path
      puts
    end
  end

  def page_paths
    @page_paths ||= Dir[File.join(@pages_dir, 'mov--*')].shuffle
  end

  def download(page_path)
    name_base = File.basename(page_path, '.html')
    if Dir[File.join(@output_dir), "#{name_base}--*"].empty?
      puts "--- #{page_path}"
      return
    else
      puts "==> #{page_path}"
    end

    page = File.read(page_path)
    case page
    when /Eviry.Player.embedkey="(.+?)"/m
      Strategies::Eviry.new(page, $1, dir: @output_dir, name_base: name_base).run
    when /<video /
      Strategies::Mp4.new(page, dir: @output_dir, name_base: name_base).run
    when /(movie_\d+)\(\);?/
      Strategies::Flv.load_index File.join(@pages_dir, 'movie.js')
      Strategies::Flv.new(page, $1, dir: @output_dir, name_base: name_base).run
    else
      raise "Unknown format"
    end
    sleep(5)
  end

  module Strategies
    class Base
      UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3659.0 Safari/537.36'

      def initialize(page, dir:, name_base:)
        @page = page
        @dir = dir
        @name_base = name_base
      end

      def output_path(suffix)
        File.join(@dir, "#{@name_base}--#{suffix}")
      end

      def curl(url, to, safe: true)
        out = safe ? "#{to}.progress" : to
        puts " * #{url} => #{to}"
        system("curl", "-A", UA, "-o", out, "-f", url) or raise "curl failed #{url.inspect}"
        File.rename out, to if safe
      end

      def get(url)
        puts " + #{url}"
        open(url, 'User-Agent' => UA, &:read)
      end

      def html
        @html ||= Nokogiri::HTML(@page)
      end
    end

    class Flv < Base
      def self.load_index(path)
        js = File.read(path)
        @index ||= js.each_line.slice_before(/^function movie_/).map {|_| [_.first.match(/function (.+?)\(\)/)[1], _[1..-1].join.match(/MPass=(http.+?)(?:[&;]|')/)[1]] }.to_h
      end

      def self.index
        @index
      end

      def initialize(page, key, dir:, name_base:)
        super(page, dir: dir, name_base: name_base)
        @key = key
      end

      def run
        title = html.at('body p').inner_text.gsub(/\r?\n/, ' ').strip
	src = self.class.index.fetch(@key)
        puts " * #{src}"
        puts "   #{title}"

        curl(src, output_path("#{title}.flv"))
      end
    end

    class Mp4 < Base
      def run
        title = html.at('body p').inner_text.gsub(/\r?\n/, ' ').strip
        src = html.at('video source')['src']
        puts " * #{src}"
        puts "   #{title}"

        curl(src, output_path("#{title}.mp4"))
      end
    end

    class Eviry < Base
      BASE_URL = 'https://finn-neo.com/contents/wuglove/movie/'
      def initialize(page, key, dir:, name_base:)
        super(page, dir: dir, name_base: name_base)
        @key = key
      end

      def run
        title = info.dig('param_basic', 'title').gsub(/\.mov$/,'')
        m3u8 = info.fetch('url')

        curl(m3u8, output_path("playlist.m3u8"))

        puts " * #{m3u8}"
        puts "   #{title}"
        progress = output_path("progress.mkv")
        system("ffmpeg", "-i", m3u8, "-c:v", "copy", "-c:a", "copy", progress) or raise "ffmpeg failed"
        File.rename progress, output_path("#{title}.mkv")
      end

      def info
        callback = generate_callback()
        url = "https://cc.miovp.com/get_info" \
          "?host=#{URI.encode_www_form_component(init.fetch('host'))}" \
          "&id_vhost=#{URI.encode_www_form_component(init.fetch('id_vhost'))}" \
          "&id_contents=#{URI.encode_www_form_component(init.fetch('id_contents'))}" \
          "&videotype=#{URI.encode_www_form_component(init.fetch('videotype'))}" \
          "&callback=#{callback}"
        @info ||= jsonp(get(url), callback)
      end

      def init
        referer = "#{BASE_URL}#{@name_base.gsub(/--/,'/')}"
        callback = generate_callback()
        @init ||= jsonp(get("https://cc.miovp.com/init?embedkey=#{URI.encode_www_form_component(@key)}&flash=0&refererurl=#{URI.encode_www_form_component(referer)}&callback=#{callback}"), callback)
      end

      def generate_callback
        "Millvi0#{rand.to_s[2..-1]}_#{(Time.now.to_f * 1000).to_i}"
      end

      def jsonp(js, callback)
        JSON.parse js.sub(/\A#{Regexp.escape(callback)}\(/,'').sub(/\);?\z/,'')
      end
    end
  end
end

page_cache_dir = File.join(__dir__, 'pages')
output_dir = File.join(__dir__, 'videos')
FileUtils.mkdir_p output_dir


WugloveMovieDownload.new(page_cache_dir, output_dir).run
