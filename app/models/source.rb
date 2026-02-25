class Source < ApplicationRecord
  validates :title, presence: true
  validates :url, uniqueness: true, allow_nil: true
end
