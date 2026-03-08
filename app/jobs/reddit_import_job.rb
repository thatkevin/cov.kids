require "net/http"
require "json"

class RedditImportJob < ApplicationJob
  queue_as :default

  USERNAME  = "HadjiChippoSafri"
  BASE_URL  = "https://www.reddit.com/user/#{USERNAME}/submitted.json"
  USER_AGENT = "CoventryEvents/1.0 (Ruby/Rails)"

  CATEGORY_MAP = {
    /music|gig|concert|band|live/i          => "music",
    /irish|ceili|ceilidh|trad.*irish|irish.*trad/i => "irish",
    /folk|shanty|bluegrass|acoustic/i       => "folk",
    /comedy|stand.?up/i                     => "comedy",
    /art|exhib|galler|theatre|theater|drama|perform|dance/i => "arts",
    /sport|fitness|run|cycle|swim|football|match/i => "sport",
    /food|market|restaurant|cafe|dining/i   => "food",
    /\bdrink\b|\bpub\b|\bbar\b/i            => "drink",
    /film|cinema|screen/i                   => "film",
    /family|kids|children/i                 => "family",
    /community|charity|volunteer/i          => "community",
    /museum|heritage|historic|antiquit/i    => "museums",
    /\bhistory\b|\bhistorical\b/i           => "history",
    /quiz|trivia/i                          => "quiz",
  }.freeze

  def perform
    ImportStatus.set!(:reddit, :running)
    posts = fetch_recent_listings
    Rails.logger.info("RedditImportJob: found #{posts.size} listing(s) to check")
    posts.each { |post| process_post(post) }
    ImportStatus.set!(:reddit, :done)
  rescue => e
    ImportStatus.set!(:reddit, :error, error: e.message)
    raise
  end

  private

  def fetch_recent_listings
    uri = URI("#{BASE_URL}?limit=10&sort=new")
    req = Net::HTTP::Get.new(uri)
    req["User-Agent"] = USER_AGENT

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
    return [] unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    data.dig("data", "children")
        &.map { |c| c["data"] }
        &.select { |d| d["title"].to_s.match?(/EVENTS:\s*What'?s On in Coventry/i) } || []
  rescue => e
    Rails.logger.error("RedditImportJob: fetch failed: #{e.message}")
    []
  end

  def process_post(post)
    url = "https://www.reddit.com#{post['permalink']}"
    return if Source.exists?(url: url)

    title      = post["title"]
    week_match = title.match(/#(\d+)/)
    date_match = title.match(/\((.+?)\)/)

    source = Source.create!(
      url:          url,
      title:        title,
      week_number:  week_match ? week_match[1].to_i : nil,
      date_range:   date_match ? date_match[1].strip : nil,
      published_at: Time.at(post["created_utc"].to_f).utc,
      body:         post["selftext"],
      source_type:  "reddit"
    )

    extract_events(source)
    Rails.logger.info("RedditImportJob: imported #{source.title}")
  rescue => e
    Rails.logger.error("RedditImportJob: process_post failed: #{e.message}")
  end

  def extract_events(source)
    return if source.body.blank?

    today            = Date.current.to_s
    current_category = "other"

    source.body.each_line do |line|
      line = line.strip

      if line.match?(/^#\s+/)
        raw = line.sub(/^#+\s*/, "")
                  .gsub(/[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}\u{FE00}-\u{FEFF}]\uFE0F?/, "")
                  .strip
        current_category = map_category(raw)
        next
      end

      next unless line.start_with?("|")
      next if line.match?(/^\|[\s:-]+\|/)
      next if line.match?(/^\|\s*Event\s*\|/i)

      cols = line.split("|").map(&:strip).reject(&:empty?)
      next if cols.length < 3

      name, event_url = parse_event_cell(cols[0])
      next if name.blank?

      existing = Event.similar_to(name).first
      if existing
        existing.increment!(:times_listed)
        existing.update!(last_seen: today, source_id: existing.source_id || source.id)
      else
        Event.create!(
          name:       name,
          venue:      cols[2].presence || "Unknown",
          venue_id:   Venue.find_or_create_for(cols[2].presence)&.id,
          category:   current_category,
          date_text:  cols[1].presence,
          event_url:  event_url,
          source:     source,
          first_seen: today,
          last_seen:  today,
          status:     :pending
        )
      end
    rescue => e
      Rails.logger.error("RedditImportJob: could not save event '#{name}': #{e.message}")
    end
  end

  def parse_event_cell(cell)
    if (m = cell.match(/\[(.+?)\]\((.+?)\)/))
      [m[1].strip, m[2].strip]
    else
      [cell.gsub(/[\[\]]/, "").strip, nil]
    end
  end

  def map_category(raw)
    CATEGORY_MAP.each { |pattern, cat| return cat if raw.match?(pattern) }
    "other"
  end
end
