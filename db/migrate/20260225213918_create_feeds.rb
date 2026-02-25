class CreateFeeds < ActiveRecord::Migration[8.1]
  def change
    create_table :feeds do |t|
      t.string   :name,                 null: false
      t.string   :url,                  null: false
      t.string   :feed_type,            null: false, default: "web"
      t.boolean  :active,               null: false, default: true
      t.datetime :last_fetched_at
      t.integer  :fetch_interval_hours, null: false, default: 24

      t.timestamps
    end
    add_index :feeds, :url, unique: true
    add_index :feeds, :feed_type
    add_index :feeds, :active
  end
end
