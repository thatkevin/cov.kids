class Event < ApplicationRecord
  include ZoneDetectable

  SIMILARITY_THRESHOLD = 0.6
  CATEGORIES = %w[music folk irish comedy arts sport food drink film family community museums history quiz other].freeze
  ZONES = %w[coventry warwickshire birmingham].freeze
  VENUE_SIMILARITY_THRESHOLD = 0.75

  # Maps weekday name patterns (in event name or date_text) to Ruby wday integers (0=Sun)
  WEEKDAY_PATTERN = {
    /\bmondays?\b/i    => 1,
    /\btuesdays?\b/i   => 2,
    /\bwednesdays?\b/i => 3,
    /\bthursdays?\b/i  => 4,
    /\bfridays?\b/i    => 5,
    /\bsaturdays?\b/i  => 6,
    /\bsundays?\b/i    => 0,
  }.freeze

  UNTIL_MONTH_RE = /jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|
                    aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?/xi.freeze

  MONTH_ABBR_NUM = {
    "jan" => 1, "feb" => 2, "mar" => 3, "apr" => 4,
    "may" => 5, "jun" => 6, "jul" => 7, "aug" => 8,
    "sep" => 9, "oct" => 10, "nov" => 11, "dec" => 12,
  }.freeze

  belongs_to :source, optional: true
  belongs_to :linked_venue, class_name: "Venue", foreign_key: "venue_id", optional: true

  enum :status, { pending: "pending", approved: "approved", rejected: "rejected" }, default: "pending"

  validates :name, presence: true

  before_save :auto_set_zone

  scope :similar_to, ->(name, threshold: SIMILARITY_THRESHOLD) {
    where("similarity(name, ?) >= ?", name, threshold)
      .order(Arel.sql("similarity(name, #{connection.quote(name)}) DESC"))
  }

  # Effective display values — curated overrides take precedence over imported data.
  # The original fields (name, venue, etc.) are kept intact for duplicate detection.
  def effective_name;      curated_name.presence      || name;                        end
  def effective_venue;     curated_venue.presence     || linked_venue&.name || venue; end
  def effective_address;   linked_venue&.address;                                     end
  def effective_date_text; curated_date_text.presence || date_text;                   end
  def effective_event_url; curated_event_url.presence || event_url;                   end
  def effective_category;  curated_category.presence  || category;                    end
  def effective_zone;      linked_venue&.zone         || zone;                        end

  def curated?
    [ curated_name, curated_venue, curated_date_text, curated_event_url, curated_category ].any?(&:present?)
  end

  # For recurring events expressed as "Jazz Fridays / Until 3rd Jul", returns
  # the next calendar date that day-of-week falls on (within the until bound).
  # Falls back to start_date when one is set.
  def next_occurrence_date
    return start_date if start_date.present?

    combined = "#{effective_name} #{effective_date_text}"
    wday = WEEKDAY_PATTERN.find { |pat, _| combined.match?(pat) }&.last
    return nil unless wday

    until_date = parse_recurring_until
    today      = Date.current
    next_occ   = today + (wday - today.wday) % 7

    return nil if until_date && next_occ > until_date

    next_occ
  end

  private

  # Parse an end-date from date_text strings like "Until 3rd Jul" or "till July 3".
  def parse_recurring_until
    text = effective_date_text.to_s
    return nil unless text.match?(/\buntil\b|\btill\b/i)

    m = UNTIL_MONTH_RE.source
    day, mon = if text =~ /(\d{1,2})(?:st|nd|rd|th)?\s+(#{m})/i
      [$1.to_i, $2]
    elsif text =~ /(#{m})\s+(\d{1,2})/i
      [$2.to_i, $1]
    end

    return nil unless day && mon

    month_num = MONTH_ABBR_NUM[mon.downcase[0, 3]]
    return nil unless month_num

    # No year-bumping: if the date has passed this year, the event is over.
    # A future end date (e.g. "Until 3rd Jul" in February) naturally parses correctly.
    Date.new(Date.current.year, month_num, day) rescue nil
  end

  def auto_set_zone
    location = linked_venue&.address.presence || linked_venue&.name.presence || curated_venue.presence || venue.to_s
    self.zone = self.class.detect_zone(location)
  end
end
