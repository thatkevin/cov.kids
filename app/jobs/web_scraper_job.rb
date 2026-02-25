require "net/http"
require "open3"

class WebScraperJob < ApplicationJob
  queue_as :default

  EXTRACT_PROMPT = <<~PROMPT.freeze
    Extract all upcoming events from the provided web page content. Return ONLY a JSON array, no markdown, no explanation.
    Each element should have these fields (use null for any that are missing):
      name       - event name (required, skip if blank)
      date_text  - date/time as written in the source
      venue      - venue name
      category   - one of: music, comedy, arts, sport, food, film, family, community, other
      event_url  - URL to buy tickets or get more info

    Skip past events if dates are visible. If no events are found, return [].
  PROMPT

  def perform(feed_id)
    feed = Feed.find(feed_id)
    return unless feed.active?

    html = fetch(feed.url)
    return unless html

    text = strip_html(html)
    return if text.blank?

    source = Source.find_or_initialize_by(url: feed.url)
    source.update!(
      title:        feed.name,
      source_type:  "web",
      body:         text,
      published_at: Time.current
    )

    events_json = run_claude(EXTRACT_PROMPT + "\n\nPage content:\n#{text.slice(0, 10_000)}")
    save_events(events_json, source)
    feed.mark_fetched!

    Rails.logger.info("WebScraperJob [#{feed.url}]: done")
  end

  private

  def fetch(url)
    uri      = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: 10, read_timeout: 20) do |h|
      h.get(uri.request_uri, "User-Agent" => "CoventryEvents/1.0")
    end
    return nil unless response.is_a?(Net::HTTPSuccess)
    response.body.force_encoding("UTF-8").encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
  rescue => e
    Rails.logger.error("WebScraperJob: fetch failed for #{url}: #{e.message}")
    nil
  end

  def strip_html(html)
    # Remove scripts, styles, nav, header, footer, aside
    cleaned = html
      .gsub(/<(script|style|nav|header|footer|aside|noscript)[^>]*>.*?<\/\1>/im, " ")
      .gsub(/<!--.*?-->/m, " ")
      .gsub(/<[^>]+>/, " ")          # strip remaining tags
      .gsub(/&nbsp;/, " ")
      .gsub(/&amp;/, "&")
      .gsub(/&lt;/, "<")
      .gsub(/&gt;/, ">")
      .gsub(/&#\d+;/, " ")
      .gsub(/&[a-z]+;/, " ")
      .gsub(/[ \t]+/, " ")           # collapse spaces
      .gsub(/\n{3,}/, "\n\n")        # collapse blank lines
      .strip
    cleaned
  end

  def run_claude(prompt)
    env  = { "CLAUDECODE" => nil }
    args = [ "claude", "--print" ]
    stdout, stderr, _status = Open3.capture3(env, *args, stdin_data: prompt)
    Rails.logger.error("WebScraperJob claude stderr: #{stderr}") if stderr.present?
    stdout
  rescue => e
    Rails.logger.error("WebScraperJob: claude invocation failed: #{e.message}")
    "[]"
  end

  def save_events(raw, source)
    events = JSON.parse(strip_fences(raw))
    today  = Date.current.to_s

    events.each do |data|
      next if data["name"].blank?

      existing = Event.similar_to(data["name"]).first
      if existing
        existing.increment!(:times_listed)
        existing.update!(last_seen: today)
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
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("WebScraperJob: could not save event '#{data["name"]}': #{e.message}")
    end
  rescue JSON::ParserError => e
    Rails.logger.error("WebScraperJob: could not parse Claude response: #{e.message}\nRaw: #{raw.slice(0, 200)}")
  end

  def strip_fences(text)
    text.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
  end
end
