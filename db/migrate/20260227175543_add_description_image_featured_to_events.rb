class AddDescriptionImageFeaturedToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :description, :text
    add_column :events, :image_url, :string
    add_column :events, :featured, :boolean, default: false, null: false
  end
end
