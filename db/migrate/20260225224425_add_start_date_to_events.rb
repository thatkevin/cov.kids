class AddStartDateToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :start_date, :date
  end
end
