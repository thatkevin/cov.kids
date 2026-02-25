class Source < ApplicationRecord
  has_many :events, dependent: :nullify

  validates :title, presence: true
  validates :url, uniqueness: true, allow_nil: true
end
