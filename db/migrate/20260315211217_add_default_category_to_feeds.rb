class AddDefaultCategoryToFeeds < ActiveRecord::Migration[8.1]
  def change
    add_column :feeds, :default_category, :string
  end
end
