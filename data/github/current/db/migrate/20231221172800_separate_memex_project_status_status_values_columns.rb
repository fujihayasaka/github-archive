class SeparateMemexProjectStatusStatusValuesColumns < ActiveRecord::Migration[7.2]
  use_connection_class ApplicationRecord::Domain::Memexes

  def change
    change_table :memex_project_statuses, bulk: true do |t|
      t.string :status_id, null: true, limit: 25
      t.date :start_date, null: true
      t.date :target_date, null: true
    end
  end
end
