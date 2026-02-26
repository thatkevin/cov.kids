class AddAliasesToVenues < ActiveRecord::Migration[8.1]
  def change
    add_column :venues, :aliases, :text, array: true, default: []
  end
end
