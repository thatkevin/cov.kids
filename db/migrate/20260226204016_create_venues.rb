class CreateVenues < ActiveRecord::Migration[8.1]
  def change
    create_table :venues do |t|
      t.string :name, null: false
      t.string :address
      t.string :zone, null: false, default: "coventry"
      t.timestamps
    end

    add_index :venues, :name, using: :gin, opclass: :gin_trgm_ops
  end
end
