class AddZoneToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :zone, :string, default: "coventry", null: false
    add_index  :events, :zone
  end
end
