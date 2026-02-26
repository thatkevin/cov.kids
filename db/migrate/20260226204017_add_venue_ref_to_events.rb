class AddVenueRefToEvents < ActiveRecord::Migration[8.1]
  def change
    add_reference :events, :venue, null: true, foreign_key: true
    add_column    :events, :venue_room, :string
  end
end
