require "net/http"
require "icalendar"

class IcalImportJob < ApplicationJob
  queue_as :default

  CATEGORY_MAP = {
    /folk|shanty|trad|ceilidh|ceili|ballad|bluegrass|acoustic/i    => "folk",
    /concert|gig|singaround|singers|performers|club.guest/i        => "music",
    /workshop/i                                                     => "other",
    /comedy/i                                                       => "comedy",
    /art|exhib|theatre|theater|dance|drama/i                       => "arts",
    /sport|fitness|run/i                                            => "sport",
    /ale.festival|beer.festival|pub.session|morris|folk.pub/i      => "drink",
    /food|market/i                                                  => "food",
    /\bdrink\b/i                                                    => "drink",
    /film|cinema/i                                                  => "film",
    /family|kids|children/i                                        => "family",
    /community|charity/i                                           => "community"
  }.freeze

  # perform(feed_url, source_type: "ical", source_name: nil)
  def perform(feed_url, source_type: "ical", source_name: nil)
    @default_category = source_name.to_s.match?(/folk/i) ? "folk" : "other"
    ics = fetch(feed_url)
    return unless ics

    calendars = Icalendar::Calendar.parse(ics)
    today      = Date.current
    today_s    = today.to_s

    source = Source.find_or_initialize_by(url: feed_url)
    source.update!(
      title:        source_name || calendar_name(calendars) || feed_url,
      source_type:  source_type,
      published_at: Time.current
    )

    imported = 0
    updated  = 0

    calendars.each do |cal|
      cal.events.each do |ev|
        next if ev.summary.blank?
        next if ev.categories.to_a.join(" ").match?(/cancel|postponed/i)

        start_date = date_of(ev.dtstart)
        next if start_date && start_date < today - 1

        ticket_url = ticket_url_from(ev) || ev.url.to_s.presence
        start_date = date_of(ev.dtstart)

        existing = Event.similar_to(ev.summary.to_s).first
        if existing
          best_url = ticket_url || (existing.event_url.presence if existing.event_url&.match?(TICKET_DOMAINS)) || existing.event_url
          existing.update!(
            last_seen:  today_s,
            source_id:  existing.source_id || source.id,
            event_url:  best_url,
            start_date: existing.start_date || start_date
          )
          updated += 1
        else
          Event.create!(
            name:       ev.summary.to_s,
            venue:      ev.location.to_s.presence,
            venue_id:   Venue.find_or_create_for(ev.location.to_s.presence)&.id,
            category:   map_category(ev.categories.to_a.first.to_s, default: @default_category),
            date_text:  format_date(ev.dtstart, ev.dtend),
            event_url:  ticket_url,
            start_date: start_date,
            source:     source,
            first_seen: today_s,
            last_seen:  today_s,
            status:     :pending
          )
          imported += 1
        end
      rescue => e
        Rails.logger.error("IcalImportJob: could not save '#{ev.summary}': #{e.message}")
      end
    end

    Rails.logger.info("IcalImportJob [#{feed_url}]: #{imported} new, #{updated} updated")
  end

  private

  def fetch(url)
    uri      = URI(url)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |h|
      h.get(uri.request_uri, "User-Agent" => "CoventryEvents/1.0")
    end
    return nil unless response.is_a?(Net::HTTPSuccess)
    response.body
  rescue => e
    Rails.logger.error("IcalImportJob: fetch failed for #{url}: #{e.message}")
    nil
  end

  def calendar_name(calendars)
    calendars.first&.x_wr_calname&.first&.value
  end

  def date_of(dt)
    return nil unless dt
    dt.respond_to?(:to_date) ? dt.to_date : Date.parse(dt.to_s)
  rescue
    nil
  end

  def format_date(dtstart, dtend)
    return nil unless dtstart
    d = date_of(dtstart)
    return nil unless d

    result = d.strftime("%-d %B %Y")

    if dtstart.respond_to?(:hour)
      result += dtstart.strftime(", %-I:%M%p").gsub(/:00([AP]M)/, '\1').downcase
    end

    if dtend
      end_date = date_of(dtend)
      result += " – #{end_date.strftime('%-d %B %Y')}" if end_date && end_date != d
    end

    result
  end

  def map_category(raw, default: "other")
    CATEGORY_MAP.each { |pattern, cat| return cat if raw.match?(pattern) }
    default
  end

  TICKET_DOMAINS = /eventbrite\.(co\.uk|com)|humanitix\.com|skiddle\.com|ticketmaster\.co\.uk|ticketweb\.uk|wegottickets\.com|seetickets\.com|universe\.com/i
  URL_PATTERN    = %r{https?://[^\s\]"<)\\]+}

  def ticket_url_from(ev)
    desc = ev.description.to_s.gsub("\\n", "\n").gsub("&amp;", "&")
    desc.scan(URL_PATTERN).find { |url| url.match?(TICKET_DOMAINS) }
  end
end
