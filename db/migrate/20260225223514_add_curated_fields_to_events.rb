class AddCuratedFieldsToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :curated_name, :string
    add_column :events, :curated_venue, :string
    add_column :events, :curated_date_text, :string
    add_column :events, :curated_event_url, :string
    add_column :events, :curated_category, :string
  end
end
