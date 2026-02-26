class Event < ApplicationRecord
  include ZoneDetectable

  SIMILARITY_THRESHOLD = 0.6
  CATEGORIES = %w[music folk comedy arts sport food film family community other].freeze
  ZONES = %w[coventry warwickshire birmingham].freeze
  VENUE_SIMILARITY_THRESHOLD = 0.75

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

  private

  def auto_set_zone
    location = linked_venue&.address.presence || linked_venue&.name.presence || curated_venue.presence || venue.to_s
    self.zone = self.class.detect_zone(location)
  end
end
