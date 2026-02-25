class AddAdminAndReviewFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :admin, :boolean, default: false, null: false
    add_column :events, :reviewed_at, :datetime
    add_column :events, :reviewed_by, :string
  end
end
