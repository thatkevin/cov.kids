#!/usr/bin/env ruby
# Fetches all "What's On in Coventry" event listings from u/HadjiChippoSafri on Reddit
# and saves them to a CSV file in old-listings/

require "net/http"
require "json"
require "csv"
require "uri"
require "time"

USERNAME = "HadjiChippoSafri"
BASE_URL = "https://www.reddit.com/user/#{USERNAME}/submitted.json"
USER_AGENT = "CoventryEvents/1.0 (Ruby)"
OUTPUT_DIR = File.expand_path("../../old-listings", __FILE__)
OUTPUT_FILE = File.join(OUTPUT_DIR, "listings.csv")
RATE_LIMIT_SECONDS = 2

def fetch_page(after: nil)
  uri = URI(BASE_URL)
  params = { "limit" => "100", "sort" => "new" }
  params["after"] = after if after
  uri.query = URI.encode_www_form(params)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Get.new(uri)
  request["User-Agent"] = USER_AGENT

  response = http.request(request)

  unless response.is_a?(Net::HTTPSuccess)
    warn "HTTP #{response.code}: #{response.message}"
    return nil
  end

  JSON.parse(response.body)
end

def event_listing?(title)
  title.match?(/EVENTS:\s*What'?s On in Coventry/i)
end

def parse_week_number(title)
  match = title.match(/#(\d+)/)
  match ? match[1].to_i : nil
end

def parse_date_range(title)
  match = title.match(/\((.+?)\)/)
  match ? match[1].strip : nil
end

puts "Fetching event listings from u/#{USERNAME}..."

all_listings = []
after = nil
page = 0

loop do
  page += 1
  print "  Page #{page}..."

  data = fetch_page(after: after)
  break unless data

  children = data.dig("data", "children") || []
  break if children.empty?

  events = children.select { |post| event_listing?(post.dig("data", "title")) }

  events.each do |post|
    d = post["data"]
    all_listings << {
      week_number: parse_week_number(d["title"]),
      title: d["title"],
      date_range: parse_date_range(d["title"]),
      created_utc: Time.at(d["created_utc"].to_f).utc.strftime("%Y-%m-%d %H:%M:%S"),
      url: "https://www.reddit.com#{d["permalink"]}",
      score: d["score"],
      num_comments: d["num_comments"],
      selftext: d["selftext"]
    }
  end

  print " found #{events.length} listings (#{all_listings.length} total)\n"

  after = data.dig("data", "after")
  break unless after

  sleep RATE_LIMIT_SECONDS
end

all_listings.sort_by! { |l| l[:week_number] || 0 }

CSV.open(OUTPUT_FILE, "w") do |csv|
  csv << %w[week_number title date_range created_utc url score num_comments selftext]

  all_listings.each do |listing|
    csv << [
      listing[:week_number],
      listing[:title],
      listing[:date_range],
      listing[:created_utc],
      listing[:url],
      listing[:score],
      listing[:num_comments],
      listing[:selftext]
    ]
  end
end

puts "\nDone! Saved #{all_listings.length} listings to #{OUTPUT_FILE}"
