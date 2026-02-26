class AddRunStatusToFeeds < ActiveRecord::Migration[8.1]
  def change
    add_column :feeds, :last_run_status, :string, default: "idle"
    add_column :feeds, :last_run_error, :text
  end
end
