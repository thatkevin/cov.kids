class Venue < ApplicationRecord
  include ZoneDetectable

  SIMILARITY_THRESHOLD = 0.7

  has_many :events, dependent: :nullify

  validates :name, presence: true

  before_save :auto_set_zone

  scope :similar_to, ->(name, threshold: SIMILARITY_THRESHOLD) {
    where("similarity(name, ?) >= ?", name, threshold)
      .order(Arel.sql("similarity(name, #{connection.quote(name)}) DESC"))
  }

  # Find the best-matching existing venue, or create a new one.
  # Splits "Venue Name - Room" → name + room parts before matching.
  def self.find_or_create_for(raw, room: nil)
    return nil if raw.blank?

    # Strip common address suffixes to get a cleaner match candidate
    candidate = raw.split(/\s*[-–]\s*/, 2).first.strip

    similar_to(candidate).first || create!(name: candidate, address: raw == candidate ? nil : raw)
  end

  private

  def auto_set_zone
    self.zone = self.class.detect_zone(address.presence || name)
  end
end
