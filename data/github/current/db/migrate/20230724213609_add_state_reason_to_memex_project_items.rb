# typed: true

class AddStateReasonToMemexProjectItems < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    change_table :memex_project_items, bulk: true do |t|
      t.column :issue_created_at, :datetime, precision: 0
      t.column :issue_closed_at, :datetime, precision: 0
      t.column :state, "enum('closed','open')", collation: :utf8mb3_general_ci
      t.column :state_reason, :tinyint, unsigned: true
    end
  end
end
