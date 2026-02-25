class AddPgTrgmAndStatusToEvents < ActiveRecord::Migration[8.1]
  def up
    enable_extension "pg_trgm"
    add_column :events, :status, :string, default: "pending", null: false
    add_index :events, :name, using: :gin, opclass: :gin_trgm_ops
    add_index :events, :status
  end

  def down
    remove_index :events, :status
    remove_index :events, column: :name, using: :gin
    remove_column :events, :status
    disable_extension "pg_trgm"
  end
end
