class Feed < ApplicationRecord
  FEED_TYPES = %w[web ical eventbrite email reddit].freeze

  validates :name, presence: true
  validates :url, presence: true, uniqueness: true
  validates :feed_type, inclusion: { in: FEED_TYPES }
  validates :fetch_interval_hours, numericality: { greater_than: 0 }

  scope :active, -> { where(active: true) }
  scope :due, -> { active.where("last_fetched_at IS NULL OR last_fetched_at < ?", Time.current - 1.hour) }

  def due?
    last_fetched_at.nil? || last_fetched_at < fetch_interval_hours.hours.ago
  end

  def mark_fetched!
    update!(last_fetched_at: Time.current)
  end
end
