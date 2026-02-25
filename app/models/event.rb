class Event < ApplicationRecord
  validates :name, presence: true
  validates :name, uniqueness: { scope: :venue }
end
