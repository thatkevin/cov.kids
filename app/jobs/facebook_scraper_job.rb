require "ferrum"
require "cgi"
require "open3"

class FacebookScraperJob < ApplicationJob
  queue_as :default

  # Dedicated Chrome profile so Facebook login persists between runs.
  # On first run Chrome opens visibly — log in, then close. Subsequent runs reuse the session.
  PROFILE_DIR = Rails.root.join("tmp/chrome-facebook").to_s

  EXTRACT_PROMPT = <<~PROMPT.freeze
    Extract all upcoming events from this Facebook page content. Return ONLY a JSON array, no markdown, no explanation.
    Each element should have these fields (use null for any that are missing):
      name        - event name (required, skip if blank)
      date_text   - date/time as written in the source
      venue       - venue name
      category    - one of: music, folk, irish, comedy, arts, sport, food, drink, film, family, community, museums, history, quiz, tabletop, other
      event_url   - full Facebook URL to the event (from the "Event URLs found on page" list at the end — match each event to its URL)
      description - a short description of the event (1-3 sentences)
      image_url   - direct URL to an event image, if visible

    Skip past events if dates are visible. If no events are found, return [].
  PROMPT

  def perform(feed_id)
    feed = Feed.find(feed_id)
    return unless feed.active?

    text = fetch_with_chrome(feed.url)
    raise "Could not fetch #{feed.url} — check the URL and whether you are logged in to Facebook" unless text.present?

    source = Source.find_or_initialize_by(url: feed.url)
    source.update!(
      title:        feed.name,
      source_type:  "facebook",
      published_at: Time.current,
      body:         text
    )

    events_json = run_claude(EXTRACT_PROMPT + "\n\nPage content:\n#{text.slice(0, 12_000)}")
    save_events(events_json, source)

    Rails.logger.info("FacebookScraperJob [#{feed.url}]: done")
  end

  private

  def fetch_with_chrome(url)
    FileUtils.mkdir_p(PROFILE_DIR)

    # Headless by default — use FACEBOOK_HEADLESS=false to debug visually
    headless = ENV.fetch("FACEBOOK_HEADLESS", "true") != "false"

    browser = Ferrum::Browser.new(
      browser_path:    chrome_executable,
      headless:        headless,
      timeout:         60,
      process_timeout: 30,
      window_size:     [1280, 900],
      # browser_options are merged last, overriding Ferrum's own --user-data-dir tmpdir
      browser_options: { "user-data-dir" => PROFILE_DIR }
    )

    browser.go_to(url)
    wait_for_content(browser)
    scroll_to_load(browser)

    # innerText gives clean readable text
    text = strip_cookie_notice(browser.evaluate("document.body.innerText"))

    # Append event URLs separately — they're not in innerText
    event_links = extract_event_links(browser)
    if event_links.any?
      text += "\n\nEvent URLs found on page:\n" + event_links.join("\n")
    end

    text
  rescue Ferrum::TimeoutError => e
    Rails.logger.error("FacebookScraperJob: timeout fetching #{url}: #{e.message}")
    nil
  rescue => e
    Rails.logger.error("FacebookScraperJob: error fetching #{url}: #{e.message}")
    nil
  ensure
    browser&.quit
  end

  # Wait for the page to render. Facebook never fully goes idle so we ignore that timeout.
  def wait_for_content(browser)
    begin
      browser.network.wait_for_idle(timeout: 10)
    rescue Ferrum::TimeoutError
      # Expected — Facebook keeps background requests running. Content is ready regardless.
    end
    sleep 2
  end

  # Scroll down a few times to trigger lazy-loaded event cards.
  def scroll_to_load(browser)
    4.times do
      browser.evaluate("window.scrollBy(0, window.innerHeight)")
      sleep 1
    end
  end

  def chrome_executable
    candidates = [
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium",
      "/usr/bin/google-chrome",
      "/usr/bin/chromium-browser",
      "/usr/bin/chromium"
    ]
    candidates.find { |p| File.executable?(p) } ||
      raise("Chrome not found — install Google Chrome or set the path in FacebookScraperJob#chrome_executable")
  end

  def run_claude(prompt)
    env  = { "CLAUDECODE" => nil }
    args = ["claude", "--print"]
    stdout, stderr, _status = Open3.capture3(env, *args, stdin_data: prompt)
    Rails.logger.error("FacebookScraperJob claude stderr: #{stderr}") if stderr.present?
    stdout
  rescue => e
    Rails.logger.error("FacebookScraperJob: claude invocation failed: #{e.message}")
    "[]"
  end

  def save_events(raw, source)
    events = JSON.parse(strip_fences(raw))
    today  = Date.current.to_s

    events.each do |data|
      next if data["name"].blank?

      name  = CGI.unescapeHTML(data["name"].to_s).strip
      venue = CGI.unescapeHTML(data["venue"].to_s).strip.presence

      existing = Event.similar_to(name).first
      if existing
        existing.increment!(:times_listed)
        updates = { last_seen: today }
        updates[:event_url] = data["event_url"] if existing.event_url.blank? && data["event_url"].present?
        existing.update!(updates)
      else
        Event.create!(
          name:        name,
          venue:       venue,
          venue_id:    Venue.find_or_create_for(data["venue"].presence)&.id,
          category:    data["category"],
          date_text:   data["date_text"],
          start_date:  Event.parse_start_date(data["date_text"]),
          event_url:   data["event_url"],
          description: CGI.unescapeHTML(data["description"].to_s).strip.presence,
          image_url:   data["image_url"].presence,
          source:      source,
          first_seen:  today,
          last_seen:   today,
          status:      :pending
        )
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error("FacebookScraperJob: could not save event '#{data["name"]}': #{e.message}")
    end
  rescue JSON::ParserError => e
    Rails.logger.error("FacebookScraperJob: could not parse Claude response: #{e.message}\nRaw: #{raw.slice(0, 200)}")
  end

  # Pull all /events/NNNNN links out of the DOM.
  def extract_event_links(browser)
    browser.evaluate(<<~JS).uniq
      Array.from(document.querySelectorAll('a[href*="/events/"]'))
        .map(a => a.href)
        .filter(h => /facebook\\.com\\/events\\/\\d+/.test(h))
    JS
  rescue => e
    Rails.logger.error("FacebookScraperJob: could not extract event links: #{e.message}")
    []
  end

  # Remove the cookie consent wall Facebook appends — it confuses Claude into returning [].
  def strip_cookie_notice(text)
    return text unless text
    text.gsub(/Allow the use of cookies from Facebook.*\z/m, "").strip
  end

  def strip_fences(text)
    text.gsub(/\A```(?:json)?\s*\n?/, "").gsub(/\n?```\s*\z/, "").strip
  end
end
