require "net/http"
require "open3"
require "cgi"
require "tempfile"
require "uri"

class WebScraperJob < ApplicationJob
  queue_as :default

  EXTRACT_PROMPT = <<~PROMPT.freeze
    Extract all upcoming events from the provided web page content. Return ONLY a JSON array, no markdown, no explanation.
    Each element should have these fields (use null for any that are missing):
      name        - event name (required, skip if blank)
      date_text   - date/time as written in the source
      venue       - venue name
      category    - one of: music, folk, irish, comedy, arts, sport, food, drink, film, family, community, museums, history, quiz, tabletop, other
      event_url   - URL to buy tickets or get more info — ONLY use a URL that appears verbatim in the content (shown as [https://...]), never construct or guess one
      description - a short description of the event (1-3 sentences), taken from the page content
      image_url   - direct URL to an image for the event (shown as [image: https://...]), if present

    Skip past events if dates are visible. If no events are found, return [].
  PROMPT

  IMAGE_EXTRACT_PROMPT = <<~PROMPT.freeze
    This is an event flyer or poster image. Extract the event details and return ONLY a JSON array, no markdown, no explanation.
    Each element should have these fields (use null for any that are missing):
      name        - event name (required, skip if blank)
      date_text   - date/time as written on the flyer
      venue       - venue name
      category    - one of: music, folk, irish, comedy, arts, sport, food, drink, film, family, community, museums, history, quiz, tabletop, other
      event_url   - URL to buy tickets or get more info, if shown
      description - a short description of the event (1-3 sentences)

    If this is not an event flyer or no events are found, return [].
  PROMPT

  # Image paths that are clearly UI/theme assets, not event flyers
  SKIP_IMAGE_PATTERN = /logo|icon|avatar|banner|badge|button|arrow|spinner|placeholder|theme|wp-content\/themes/i
  FLYER_IMAGE_PATTERN = /wp-content\/uploads|uploads\/|flyer|poster|event/i

  def perform(feed_id)
    feed = Feed.find(feed_id)
    return unless feed.active?

    html = fetch(feed.url)
    raise "Could not fetch #{feed.url} — check the URL and whether the site blocks bots" unless html

    source = Source.find_or_initialize_by(url: feed.url)
    source.update!(
      title:        feed.name,
      source_type:  "web",
      published_at: Time.current
    )

    # Extract text
    text = strip_html(html, feed.url)
    if text.present?
      source.update!(body: text)
      events_json = run_claude(EXTRACT_PROMPT + "\n\nPage content:\n#{text.slice(0, 20_000)}")
      save_events(events_json, source)
    end

    # Extract and process image flyers
    image_urls = extract_flyer_urls(html, feed.url)
    Rails.logger.info("WebScraperJob [#{feed.url}]: found #{image_urls.length} flyer image(s)")
    image_urls.each { |url| process_image(url, source) }

    Rails.logger.info("WebScraperJob [#{feed.url}]: done")
  end

  private

  def extract_flyer_urls(html, base_url)
    base = URI(base_url)
    urls = html.scan(/<img[^>]+src=["']([^"']+)["']/i).flatten

    urls.filter_map do |src|
      next if src.match?(SKIP_IMAGE_PATTERN)
      next unless src.match?(FLYER_IMAGE_PATTERN) || src.match?(/\.(jpg|jpeg|png|webp)(\?|$)/i)

      begin
        abs = URI.join(base, src).to_s
        abs.start_with?("http") ? abs : nil
      rescue
        nil
      end
    end.uniq.first(10) # cap at 10 images per page
  end

  def process_image(image_url, source)
    ext  = File.extname(URI(image_url).path).downcase.presence || ".jpg"
    data = fetch_binary(image_url)
    return unless data

    Tempfile.create(["ck_flyer", ext]) do |f|
      f.binmode
      f.write(data)
      f.flush
      events_json = run_claude_with_image(IMAGE_EXTRACT_PROMPT, f.path)
      save_events(events_json, source, default_image_url: image_url)
    end
  rescue => e
    Rails.logger.error("WebScraperJob: failed to process image #{image_url}: #{e.message}")
  end

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

  def fetch_binary(url)
    uri      = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                               open_timeout: 10, read_timeout: 30) do |h|
      h.get(uri.request_uri, "User-Agent" => "CoventryEvents/1.0")
    end
    return nil unless response.is_a?(Net::HTTPSuccess)
    response.body
  rescue => e
    Rails.logger.error("WebScraperJob: fetch_binary failed for #{url}: #{e.message}")
    nil
  end

  def strip_html(html, base_url = nil)
    base = base_url ? URI(base_url) : nil
    html
      .gsub(/<(script|style|nav|header|footer|aside|noscript)[^>]*>.*?<\/\1>/im, " ")
      .gsub(/<!--.*?-->/m, " ")
      .gsub(/<img\s[^>]*src=["']([^"']+)["'][^>]*/i) {
        src = $1
        if base
          begin; src = URI.join(base, src).to_s; rescue URI::Error; end
        end
        src.match?(/\.(jpg|jpeg|png|webp|gif)/i) ? " [image: #{src}] " : " "
      }
      .gsub(/<a\s[^>]*href=["']([^"']+)["'][^>]*>/i) {
        href = $1
        if base
          begin; href = URI.join(base, href).to_s; rescue URI::Error; end
        end
        " [#{href}] "
      }
      .gsub(/<[^>]+>/, " ")
      .gsub(/&nbsp;/, " ").gsub(/&amp;/, "&").gsub(/&lt;/, "<").gsub(/&gt;/, ">")
      .gsub(/&#\d+;/, " ").gsub(/&[a-z]+;/, " ")
      .gsub(/[ \t]+/, " ")
      .gsub(/\n{3,}/, "\n\n")
      .strip
  end

  def run_claude(prompt)
    env  = { "CLAUDECODE" => nil }
    args = ["claude", "--print"]
    stdout, stderr, _status = Open3.capture3(env, *args, stdin_data: prompt)
    Rails.logger.error("WebScraperJob claude stderr: #{stderr}") if stderr.present?
    stdout
  rescue => e
    Rails.logger.error("WebScraperJob: claude invocation failed: #{e.message}")
    "[]"
  end

  def run_claude_with_image(prompt, file_path)
    env  = { "CLAUDECODE" => nil }
    full_prompt = "#{prompt}\n\nAnalyse the image at this path: #{file_path}"
    args = ["claude", "--print", "--add-dir", File.dirname(file_path)]
    stdout, stderr, _status = Open3.capture3(env, *args, stdin_data: full_prompt)
    Rails.logger.error("WebScraperJob claude image stderr: #{stderr}") if stderr.present?
    stdout
  rescue => e
    Rails.logger.error("WebScraperJob: claude image invocation failed: #{e.message}")
    "[]"
  end

  def save_events(raw, source, default_image_url: nil)
    events = JSON.parse(strip_fences(raw))
    today  = Date.current.to_s

    events.each do |data|
      next if data["name"].blank?

      name      = CGI.unescapeHTML(data["name"].to_s).strip
      venue     = CGI.unescapeHTML(data["venue"].to_s).strip.presence
      image_url = data["image_url"].presence || default_image_url

      existing = Event.similar_to(name).first
      if existing
        existing.increment!(:times_listed)
        updates = { last_seen: today }
        needs_url = data["event_url"].present? &&
                    data["event_url"] != source.url &&
                    (existing.event_url.blank? ||
                     !existing.event_url.to_s.start_with?("http") ||
                     existing.event_url == source.url)
        updates[:event_url]   = data["event_url"] if needs_url
        updates[:image_url]   = image_url if existing.image_url.blank? && image_url.present?
        existing.update!(updates)
      else
        Event.create!(
          name:        name,
          venue:       venue,
          venue_id:    Venue.find_or_create_for(data["venue"].presence)&.id,
          category:    data["category"],
          date_text:   data["date_text"],
          start_date:  Event.parse_start_date(data["date_text"]),
          event_url:   data["event_url"].presence || source.url,
          description: CGI.unescapeHTML(data["description"].to_s).strip.presence,
          image_url:   image_url,
          source:      source,
          first_seen:  today,
          last_seen:   today,
          status:      :pending
        )
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("WebScraperJob: could not save event '#{data["name"]}': #{e.message}")
    end
  rescue JSON::ParserError => e
    Rails.logger.error("WebScraperJob: could not parse Claude response: #{e.message}\nRaw: #{raw.slice(0, 200)}")
  end

  def strip_fences(text)
    text.gsub(/\A```(?:json)?\s*\n?/, "").gsub(/\n?```\s*\z/, "").strip
  end
end
