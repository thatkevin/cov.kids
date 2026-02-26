class CreateImportStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :import_statuses do |t|
      t.string :key, null: false
      t.string :status, null: false, default: "idle"
      t.text :last_run_error
      t.datetime :last_run_at

      t.timestamps
    end

    add_index :import_statuses, :key, unique: true
  end
end
