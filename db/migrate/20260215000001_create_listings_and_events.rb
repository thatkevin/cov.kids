class CreateListingsAndEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :listings do |t|
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

    add_index :listings, :week_number
    add_index :listings, :reddit_url, unique: true

    create_table :events do |t|
      t.string :name, null: false
      t.string :category
      t.string :venue
      t.string :date_text
      t.string :event_url
      t.integer :times_listed, default: 1
      t.string :first_seen
      t.string :last_seen

      t.timestamps
    end

    add_index :events, :category
    add_index :events, :venue
    add_index :events, [:name, :venue], unique: true
  end
end
