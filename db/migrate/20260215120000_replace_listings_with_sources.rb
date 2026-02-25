class ReplaceListingsWithSources < ActiveRecord::Migration[8.0]
  def change
    create_table :sources do |t|
      t.integer :week_number
      t.string :title, null: false
      t.string :date_range
      t.datetime :published_at
      t.string :url
      t.text :body
      t.string :source_type, null: false, default: "reddit"

      t.timestamps
    end

    add_index :sources, :url, unique: true
    add_index :sources, :week_number
    add_index :sources, :source_type

    drop_table :listings do |t|
      t.integer :week_number
      t.string :title, null: false
      t.string :date_range
      t.datetime :posted_at
      t.string :reddit_url
      t.integer :score
      t.integer :num_comments
      t.text :selftext

      t.timestamps
    end
  end
end
