class AddGinIndexToEventsVenue < ActiveRecord::Migration[8.1]
  def change
    remove_index :events, :venue, if_exists: true
    add_index :events, :venue, using: :gin, opclass: :gin_trgm_ops
  end
end
