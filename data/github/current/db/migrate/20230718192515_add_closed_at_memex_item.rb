# typed: true

class AddClosedAtMemexItem < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    add_column :memex_project_items, :closed_at, :datetime, precision: 0
  end
end
