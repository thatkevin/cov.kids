require "net/http"
require "open3"

class EventbriteImportJob < ApplicationJob
  queue_as :default

  BASE_URL   = "https://www.eventbrite.co.uk/d/united-kingdom--coventry/events/"
  USER_AGENT = "CoventryEvents/1.0"

  EXTRACT_PROMPT = <<~PROMPT.freeze
    Extract all upcoming events from this Eventbrite search results page. Return ONLY a JSON array, no markdown, no explanation.
    Each element should have these fields (use null for any that are missing):
      name       - event name (required, skip if blank)
      date_text  - date/time as written on the page
      venue      - venue or location name
      category   - one of: music, comedy, arts, sport, food, film, family, community, other
      event_url  - full Eventbrite URL for the event (e.g. https://www.eventbrite.co.uk/e/...)

    Only include events in or near Coventry. Skip events that are clearly in other cities.
    If no events are found, return [].
  PROMPT

  def perform
    source = Source.find_or_initialize_by(url: BASE_URL)
    source.update!(
      title:        "Eventbrite Coventry",
      source_type:  "web",
      published_at: Time.current
    )

    total = 0
    [ BASE_URL,
      "https://www.eventbrite.co.uk/d/united-kingdom--coventry/music--events/",
      "https://www.eventbrite.co.uk/d/united-kingdom--coventry/arts--events/",
      "https://www.eventbrite.co.uk/d/united-kingdom--coventry/food-and-drink--events/"
    ].each do |url|
      html = fetch(url)
      next unless html

      text = strip_html(html)
      next if text.blank?

      events_json = run_claude(EXTRACT_PROMPT + "\n\nPage content:\n#{text.slice(0, 12_000)}")
      count = save_events(events_json, source)
      total += count
      Rails.logger.info("EventbriteImportJob [#{url}]: #{count} events")
    end

    Rails.logger.info("EventbriteImportJob: #{total} total events processed")
  end

  private

  def fetch(url)
    uri      = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                               open_timeout: 15, read_timeout: 30) do |h|
      h.get(uri.request_uri, "User-Agent" => USER_AGENT, "Accept-Language" => "en-GB,en;q=0.9")
    end
    return nil unless response.is_a?(Net::HTTPSuccess)
    response.body.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
  rescue => e
    Rails.logger.error("EventbriteImportJob: fetch failed for #{url}: #{e.message}")
    nil
  end

  def strip_html(html)
    html
      .gsub(/<(script|style|nav|header|footer|aside|noscript)[^>]*>.*?<\/\1>/im, " ")
      .gsub(/<!--.*?-->/m, " ")
      .gsub(/<[^>]+>/, " ")
      .gsub(/&nbsp;/, " ").gsub(/&amp;/, "&").gsub(/&lt;/, "<").gsub(/&gt;/, ">")
      .gsub(/&#\d+;/, " ").gsub(/&[a-z]+;/, " ")
      .gsub(/[ \t]+/, " ")
      .gsub(/\n{3,}/, "\n\n")
      .strip
  end

  def run_claude(prompt)
    env  = { "CLAUDECODE" => nil }
    args = [ "claude", "--print" ]
    stdout, stderr, _status = Open3.capture3(env, *args, stdin_data: prompt)
    Rails.logger.error("EventbriteImportJob claude stderr: #{stderr}") if stderr.present?
    stdout
  rescue => e
    Rails.logger.error("EventbriteImportJob: claude invocation failed: #{e.message}")
    "[]"
  end

  def save_events(raw, source)
    events = JSON.parse(strip_fences(raw))
    today  = Date.current.to_s
    count  = 0

    events.each do |data|
      next if data["name"].blank?

      existing = Event.similar_to(data["name"]).first
      if existing
        existing.increment!(:times_listed)
        existing.update!(
          last_seen:  today,
          source_id:  existing.source_id || source.id,
          event_url:  existing.event_url.presence || data["event_url"]
        )
      else
        Event.create!(
          name:       data["name"],
          venue:      data["venue"].presence,
          category:   data["category"],
          date_text:  data["date_text"],
          event_url:  data["event_url"],
          source:     source,
          first_seen: today,
          last_seen:  today,
          status:     :pending
        )
        count += 1
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("EventbriteImportJob: could not save '#{data["name"]}': #{e.message}")
    end

    count
  rescue JSON::ParserError => e
    Rails.logger.error("EventbriteImportJob: could not parse Claude response: #{e.message}\nRaw: #{raw.slice(0, 200)}")
    0
  end

  def strip_fences(text)
    text.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
  end
end
