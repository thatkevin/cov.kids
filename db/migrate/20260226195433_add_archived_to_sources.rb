class AddArchivedToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :archived, :boolean, default: false, null: false
    add_index :sources, :archived
  end
end
