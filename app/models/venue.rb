require "cgi"

class Venue < ApplicationRecord
  include ZoneDetectable

  SIMILARITY_THRESHOLD = 0.7

  has_many :events, dependent: :nullify

  validates :name, presence: true

  before_save :capture_alias_on_rename
  before_save :auto_set_zone

  scope :similar_to, ->(name, threshold: SIMILARITY_THRESHOLD) {
    where("similarity(name, ?) >= ?", name, threshold)
      .order(Arel.sql("similarity(name, #{connection.quote(name)}) DESC"))
  }

  # Find the best-matching existing venue, or create a new one.
  # Matching order:
  #   1. Fuzzy similarity on name (pg_trgm)
  #   2. Exact match against stored aliases (previous names saved on rename)
  #   3. Create new record
  def self.find_or_create_for(raw, room: nil)
    return nil if raw.blank?

    clean = CGI.unescapeHTML(raw.to_s).strip
    return nil if clean.blank?

    candidate = clean.split(/\s*[-–]\s*/, 2).first.strip

    similar_to(candidate).first ||
      find_by("? = ANY(aliases)", candidate) ||
      find_by("? = ANY(aliases)", clean) ||
      create!(name: candidate, address: clean == candidate ? nil : clean)
  end

  private

  # When the name changes, save the old name as an alias so future imports
  # using the old raw string still resolve to this venue.
  def capture_alias_on_rename
    return unless name_changed? && name_was.present?
    self.aliases = (aliases | [name_was]).uniq
  end

  def auto_set_zone
    self.zone = self.class.detect_zone(address.presence || name)
  end
end
