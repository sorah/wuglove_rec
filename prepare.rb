require 'nokogiri'
require 'open-uri'
require 'fileutils'

UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_2) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/73.0.3659.0 Safari/537.36'
INDEX_URL = 'https://finn-neo.com/contents/wuglove/movie/index.html'
BASE_URL = 'https://finn-neo.com/contents/wuglove/movie/'
MOVIEJS_URL = 'https://finn-neo.com/contents/wuglove/movie/mov/js/movie.js'
COOKIE = ENV.fetch('WUGLOVE_COOKIE')

def get(url)
  open(url, 'User-Agent' => UA, 'Cookie' => COOKIE, &:read)
end

page_cache_dir = File.join(__dir__, 'pages')
FileUtils.mkdir_p page_cache_dir

index = Nokogiri::HTML(get(INDEX_URL))

moviejs_path = File.join(page_cache_dir, 'movie.js')
File.write moviejs_path, get(MOVIEJS_URL) unless File.exist?(moviejs_path)

index.search('a.movpopup2, a.movpopup').to_a.shuffle.each do |link|
  cache_path = File.join(page_cache_dir, link['href'].sub(%r{/}, '--'))
  if File.exist?(cache_path)
    puts " v #{link['href']}"
    next
  end
  puts " * #{link['href']}"

  page_url = "#{BASE_URL}#{link['href']}".gsub(%r{/+},'/').sub(%r{https?:/}, '\0/')
  raise page_url if page_url.include?("./")
  puts "   #{page_url} > #{cache_path}"

  page = get(page_url)
  File.write cache_path, page

  sleep rand(5)
end
